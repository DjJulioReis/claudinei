#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// Driver nativo do ESP32 para UART
#include "driver/uart.h"
#include "soc/soc.h"

// --- INCLUSÃO COMPATÍVEL COM O CORE NOVO DO ESP32 ---
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- INCLUSÃO DA LOGO CUSTOMIZADA ---
#include "MILETO_LOGO_1.h"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 oled(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

Preferences preferences;

// --- CONFIGURAÇÃO DA UART NATIVA PARA DMX512 / RDM ---
#define DMX_UART_NUM UART_NUM_1
#define DMX_RX_PIN 20
#define DMX_TX_PIN 21

// Controle de direção do transceptor RS-485 para RDM
// Nota: Se usar um módulo com controle de fluxo automático (ex: MAX13487),
// este pino não é necessário. Caso use MAX485 tradicional, defina um pino livre (ex: GPIO 3 ou 10)
#define RS485_DIR_PIN -1 // Definir GPIO se necessário para DE/RE físico

static QueueHandle_t dmx_queue;
uint8_t raw_dmx_buf[515];
int dmx_idx = 0;
bool dmx_em_frame = false;

// --- CONFIGURAÇÃO UUIDs BLE ---
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
String comandoPendente = "";
bool novoComandoBle = false;

// --- MAPEAMENTO DE PINOS DOS MOSFETS ---
#define MOSFET_CH1 0
#define MOSFET_CH2 1
#define MOSFET_CH3 5
#define MOSFET_CH4 4

// Painel de Controle Físico (Definições para ESP32-C3 Super Mini)
#define BTN_MUDAR_CAMPO 6
#define BTN_FRENTE 7
#define BTN_VOLTA 10
#define BTN_GRAVAR 2
#define CHAVE_DMX_MANUAL 3   // Pino do botão alternador de modo DMX/Manual

#define PWM_FREQ 4000
#define PWM_RES 8

// --- DISPLAY OLED ---
#define OLED_SDA 8
#define OLED_SCL 9

enum FasesMenu { FASE_MODO, FASE_CAMPO, FASE_VALOR };
FasesMenu faseAtual = FASE_MODO;

bool sistemaEmModoDMX = false;
int modoAtual = 0;
int velocidad = 100;
int brilhoGeral = 255;
int enderecoDMX = 1;

int linhaSelecionada = 0;
int canalSelecionado = 0;
int brilhoCanais[4] = { 255, 255, 255, 255 };
int velocidadesCanais[4] = { 100, 100, 100, 100 };
int niveisAtuais[4] = { 0, 0, 0, 0 };

const char* nomesEfeitos[] = { "MANUAL", "FADE", "STROBO", "SEQUENC", "FIXO" };

unsigned long tempoUltimaAtividade = 0;
bool telaAcesa = true;
#define TEMPO_SLEEP_TELA 125000

unsigned long ultimaAtualizacaoEfeito = 0;
int fadeValue = 0;
bool fadeDirection = true;
bool estadoStrobo = false;
int passoAlternado = 0;
unsigned long ultimoDebounce = 0;

unsigned long ultimoPacoteDMX = 0;
bool sinalDMXAtivo = false;
bool dispositivoConectado = false;

void atualizarDisplay();
void acordaTela();
void executarEfeitos();
void writeChannel(int ch, int val);
void processarMesaDMX();
void salvarConfiguracao();
void desenharLogo(const uint8_t* bitmap);
void processarBluetooth();
void exibirTelaSalvando();
void setRS485Direction(bool transmitir);
void executarVarreduraRDM();

// --- CALLBACKS PARA O NOVO CORE ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
      dispositivoConectado = true;
    };
    void onDisconnect(BLEServer* pServer) override {
      dispositivoConectado = false;
      BLEDevice::startAdvertising();
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) override {
      String rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) {
        comandoPendente = rxValue;
        novoComandoBle = true;
      }
    }
};

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n====================================");
  Serial.println("   MILETO - FIRMWARE ESP32 C3 V5.5   ");
  Serial.println("====================================");

  pinMode(BTN_MUDAR_CAMPO, INPUT_PULLUP);
  pinMode(BTN_FRENTE, INPUT_PULLUP);
  pinMode(BTN_VOLTA, INPUT_PULLUP);
  pinMode(BTN_GRAVAR, INPUT_PULLUP);
  pinMode(CHAVE_DMX_MANUAL, INPUT_PULLUP);

  if (RS485_DIR_PIN != -1) {
    pinMode(RS485_DIR_PIN, OUTPUT);
    digitalWrite(RS485_DIR_PIN, LOW); // Modo recepção padrão
  }

  ledcAttach(MOSFET_CH1, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH2, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH3, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH4, PWM_FREQ, PWM_RES);

  Wire.begin(OLED_SDA, OLED_SCL);
  delay(100);

  if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("ERRO OLED!");
  }

  oled.setTextColor(SSD1306_WHITE);
  desenharLogo(MILETO_LOGO_1);
  delay(3000);

  preferences.begin("mileto_cfg", false);
  enderecoDMX = preferences.getInt("dmx", 1);
  modoAtual = preferences.getInt("modo", 0);
  velocidad = preferences.getInt("vel", 100);
  brilhoGeral = preferences.getInt("dim", 255);
  brilhoCanais[0] = preferences.getInt("ch1", 255);
  brilhoCanais[1] = preferences.getInt("ch2", 255);
  brilhoCanais[2] = preferences.getInt("ch3", 255);
  brilhoCanais[3] = preferences.getInt("ch4", 255);
  velocidadesCanais[0] = preferences.getInt("vch1", 100);
  velocidadesCanais[1] = preferences.getInt("vch2", 100);
  velocidadesCanais[2] = preferences.getInt("vch3", 100);
  velocidadesCanais[3] = preferences.getInt("vch4", 100);
  preferences.end();

  // --- CONFIGURAÇÃO DO BLE NATIVO ---
  BLEDevice::init("MILETO_C3");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID_TX,
                        BLECharacteristic::PROPERTY_NOTIFY
                      );
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
                                           CHARACTERISTIC_UUID_RX,
                                           BLECharacteristic::PROPERTY_WRITE
                                         );
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE Ativo e pronto para conexao.");

  // --- CONFIGURAÇÃO DA UART NATIVA (DMX512) ---
  uart_config_t uart_config = {
    .baud_rate = 250000,
    .data_bits = UART_DATA_8_BITS,
    .parity = UART_PARITY_DISABLE,
    .stop_bits = UART_STOP_BITS_2,
    .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
    .source_clk = UART_SCLK_DEFAULT
  };
  uart_param_config(DMX_UART_NUM, &uart_config);
  uart_set_pin(DMX_UART_NUM, DMX_TX_PIN, DMX_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  uart_driver_install(DMX_UART_NUM, 1024, 0, 20, &dmx_queue, 0);

  tempoUltimaAtividade = millis();
  atualizarDisplay();
}

void loop() {
  static bool ultimoEstadoConexao = false;
  if (dispositivoConectado != ultimoEstadoConexao) {
    ultimoEstadoConexao = dispositivoConectado;
    acordaTela();
    atualizarDisplay();
  }

  if (novoComandoBle) {
    processarBluetooth();
    novoComandoBle = false;
    comandoPendente = "";
  }

  if (digitalRead(CHAVE_DMX_MANUAL) == LOW) {
    delay(50);
    if (digitalRead(CHAVE_DMX_MANUAL) == LOW) {
      if (millis() - ultimoDebounce >= 250) {
        ultimoDebounce = millis();
        acordaTela();
        sistemaEmModoDMX = !sistemaEmModoDMX;

        if (!sistemaEmModoDMX) {
          preferences.begin("mileto_cfg", true);
          modoAtual = preferences.getInt("modo", 0);
          velocidad = preferences.getInt("vel", 100);
          brilhoGeral = preferences.getInt("dim", 255);
          brilhoCanais[0] = preferences.getInt("ch1", 255);
          brilhoCanais[1] = preferences.getInt("ch2", 255);
          brilhoCanais[2] = preferences.getInt("ch3", 255);
          brilhoCanais[3] = preferences.getInt("ch4", 255);
          velocidadesCanais[0] = preferences.getInt("vch1", 100);
          velocidadesCanais[1] = preferences.getInt("vch2", 100);
          velocidadesCanais[2] = preferences.getInt("vch3", 100);
          velocidadesCanais[3] = preferences.getInt("vch4", 100);
          preferences.end();
        }
        atualizarDisplay();
        while (digitalRead(CHAVE_DMX_MANUAL) == LOW) { delay(10); }
      }
    }
  }

  if (!sistemaEmModoDMX) {
    if (digitalRead(BTN_MUDAR_CAMPO) == LOW) {
      delay(50);
      if (digitalRead(BTN_MUDAR_CAMPO) == LOW) {
        if (millis() - ultimoDebounce >= 250) {
          ultimoDebounce = millis();
          acordaTela();
          if (faseAtual == FASE_CAMPO) {
            faseAtual = FASE_MODO;
            linhaSelecionada = 0;
          } else if (faseAtual == FASE_VALOR) {
            faseAtual = FASE_CAMPO;
          }
          atualizarDisplay();
          while (digitalRead(BTN_MUDAR_CAMPO) == LOW) { delay(10); }
        }
      }
    }

    if (digitalRead(BTN_FRENTE) == LOW) {
      delay(50);
      if (digitalRead(BTN_FRENTE) == LOW) {
        if (millis() - ultimoDebounce >= 150) {
          ultimoDebounce = millis();
          acordaTela();
          if (faseAtual == FASE_MODO) {
            modoAtual = (modoAtual + 1) % 5;
          } else if (faseAtual == FASE_CAMPO) {
            linhaSelecionada = (linhaSelecionada == 1) ? 2 : 1;
          } else if (faseAtual == FASE_VALOR) {
            if (linhaSelecionada == 1) {
              if (modoAtual == 0) canalSelecionado = (canalSelecionado + 1) % 4;
              else { velocidad = min(velocidad + 5, 100); }
            } else if (linhaSelecionada == 2) {
              if (modoAtual == 0) brilhoCanais[canalSelecionado] = min(brilhoCanais[canalSelecionado] + 15, 255);
              else brilhoGeral = min(brilhoGeral + 15, 255);
            }
          }
          atualizarDisplay();
          while (digitalRead(BTN_FRENTE) == LOW) { delay(10); }
        }
      }
    }

    if (digitalRead(BTN_VOLTA) == LOW) {
      delay(50);
      if (digitalRead(BTN_VOLTA) == LOW) {
        if (millis() - ultimoDebounce >= 150) {
          ultimoDebounce = millis();
          acordaTela();
          if (faseAtual == FASE_MODO) {
            modoAtual = (modoAtual <= 0) ? 4 : modoAtual - 1;
          } else if (faseAtual == FASE_CAMPO) {
            linhaSelecionada = (linhaSelecionada == 1) ? 2 : 1;
          } else if (faseAtual == FASE_VALOR) {
            if (linhaSelecionada == 1) {
              if (modoAtual == 0) canalSelecionado = (canalSelecionado <= 0) ? 3 : canalSelecionado - 1;
              else { velocidad = max(velocidad - 5, 0); }
            } else if (linhaSelecionada == 2) {
              if (modoAtual == 0) brilhoCanais[canalSelecionado] = max(brilhoCanais[canalSelecionado] - 15, 0);
              else brilhoGeral = max(brilhoGeral - 15, 0);
            }
          }
          atualizarDisplay();
          while (digitalRead(BTN_VOLTA) == LOW) { delay(10); }
        }
      }
    }

    if (digitalRead(BTN_GRAVAR) == LOW) {
      delay(50);
      if (digitalRead(BTN_GRAVAR) == LOW) {
        if (millis() - ultimoDebounce >= 250) {
          ultimoDebounce = millis();
          acordaTela();
          if (faseAtual == FASE_MODO) {
            faseAtual = FASE_CAMPO;
            linhaSelecionada = 1;
            atualizarDisplay();
          } else if (faseAtual == FASE_CAMPO) {
            faseAtual = FASE_VALOR;
            atualizarDisplay();
          } else if (faseAtual == FASE_VALOR) {
            exibirTelaSalvando();
            salvarConfiguracao();
            delay(1000);
            faseAtual = FASE_MODO;
            linhaSelecionada = 0;
            atualizarDisplay();
          }
          while (digitalRead(BTN_GRAVAR) == LOW) { delay(10); }
        }
      }
    }
  } else {
    if (digitalRead(BTN_FRENTE) == LOW) {
      delay(50);
      if (digitalRead(BTN_FRENTE) == LOW) {
        if (millis() - ultimoDebounce >= 150) {
          ultimoDebounce = millis();
          acordaTela();
          enderecoDMX = (enderecoDMX >= 512) ? 1 : enderecoDMX + 1;
          atualizarDisplay();
          while (digitalRead(BTN_FRENTE) == LOW) { delay(10); }
        }
      }
    }

    if (digitalRead(BTN_VOLTA) == LOW) {
      delay(50);
      if (digitalRead(BTN_VOLTA) == LOW) {
        if (millis() - ultimoDebounce >= 150) {
          ultimoDebounce = millis();
          acordaTela();
          enderecoDMX = (enderecoDMX <= 1) ? 512 : enderecoDMX - 1;
          atualizarDisplay();
          while (digitalRead(BTN_VOLTA) == LOW) { delay(10); }
        }
      }
    }

    if (digitalRead(BTN_GRAVAR) == LOW) {
      delay(50);
      if (digitalRead(BTN_GRAVAR) == LOW) {
        if (millis() - ultimoDebounce >= 250) {
          ultimoDebounce = millis();
          acordaTela();
          exibirTelaSalvando();
          salvarConfiguracao();
          delay(1000);
          atualizarDisplay();
          while (digitalRead(BTN_GRAVAR) == LOW) { delay(10); }
        }
      }
    }
  }

  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    oled.clearDisplay();
    oled.display();
    oled.ssd1306_command(SSD1306_DISPLAYOFF);
    telaAcesa = false;
  }

  if (sistemaEmModoDMX) processarMesaDMX();
  executarEfeitos();
}

void desenharLogo(const uint8_t* bitmap) {
  oled.clearDisplay();
  oled.drawBitmap(0, 0, bitmap, 128, 64, SSD1306_WHITE);
  oled.display();
}

void writeChannel(int ch, int val) {
  if (ch < 0 || ch > 3) return;
  niveisAtuais[ch] = val;
  switch (ch) {
    case 0: ledcWrite(MOSFET_CH1, val); break;
    case 1: ledcWrite(MOSFET_CH2, val); break;
    case 2: ledcWrite(MOSFET_CH3, val); break;
    case 3: ledcWrite(MOSFET_CH4, val); break;
  }
}

void executarEfeitos() {
  unsigned long tempoAtual = millis();
  int delayEfeito = map(velocidad, 0, 100, 800, 25);

  if (modoAtual == 0) {
    if (sistemaEmModoDMX) {
      for (int i = 0; i < 4; i++) {
        writeChannel(i, (brilhoCanais[i] * brilhoGeral) / 255);
      }
    } else {
      static unsigned long ultimosTempos[4] = {0, 0, 0, 0};
      static boolean estadosCanais[4] = {false, false, false, false};
      int delaysIndividuais[4];

      for (int i = 0; i < 4; i++) {
        if (velocidadesCanais[i] >= 100) {
          estadosCanais[i] = true;
        } else {
          delaysIndividuais[i] = map(velocidadesCanais[i], 0, 99, 800, 40);
          if (tempoAtual - ultimosTempos[i] >= (unsigned long)delaysIndividuais[i]) {
            ultimosTempos[i] = tempoAtual;
            estadosCanais[i] = !estadosCanais[i];
          }
        }
        int nivelBase = (brilhoCanais[i] * brilhoGeral) / 255;
        writeChannel(i, estadosCanais[i] ? nivelBase : 0);
      }
    }
    return;
  }

  if (brilhoGeral == 0) {
    for(int i=0; i<4; i++) writeChannel(i, 0);
    return;
  }

  switch (modoAtual) {
    case 1:
      if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito / 12) {
        ultimaAtualizacaoEfeito = tempoAtual;
        fadeValue = fadeDirection ? fadeValue + 1 : fadeValue - 1;
        if (fadeValue >= 255) { fadeValue = 255; fadeDirection = false; }
        else if (fadeValue <= 0) { fadeValue = 0; fadeDirection = true; }

        writeChannel(0, (fadeValue * brilhoGeral) / 255);
        writeChannel(1, ((255 - fadeValue) * brilhoGeral) / 255);
        writeChannel(2, ((255 - fadeValue) * brilhoGeral) / 255);
        writeChannel(3, (fadeValue * brilhoGeral) / 255);
      }
      break;

    case 2:
      if (velocidad >= 100) {
        for(int i=0; i<4; i++) writeChannel(i, brilhoGeral);
      } else {
        if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito) {
          ultimaAtualizacaoEfeito = tempoAtual;
          estadoStrobo = !estadoStrobo;
          for(int i=0; i<4; i++) writeChannel(i, estadoStrobo ? brilhoGeral : 0);
        }
      }
      break;

    case 3:
      if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito) {
        ultimaAtualizacaoEfeito = tempoAtual;
        passoAlternado = (passoAlternado + 1) % 4;
        for(int i=0; i<4; i++) writeChannel(i, (passoAlternado == i) ? brilhoGeral : 0);
      }
      break;

    case 4:
      for(int i=0; i<4; i++) writeChannel(i, brilhoGeral);
      break;
  }
}

void processarMesaDMX() {
  uart_event_t event;
  while (xQueueReceive(dmx_queue, (void*)&event, 0)) {
    if (event.type == UART_BREAK) {
      uart_flush_input(DMX_UART_NUM);
      dmx_idx = 0;
      dmx_em_frame = true;
    }
    else if (event.type == UART_DATA && dmx_em_frame) {
      size_t available_len = 0;
      uart_get_buffered_data_len(DMX_UART_NUM, &available_len);

      if (available_len > 0) {
        uint8_t temp_bytes[64];
        size_t chunk = (available_len > 64) ? 64 : available_len;
        int read_bytes = uart_read_bytes(DMX_UART_NUM, temp_bytes, chunk, 0);

        for (int i = 0; i < read_bytes; i++) {
          if (dmx_em_frame) {
            if (dmx_idx < 515) raw_dmx_buf[dmx_idx] = temp_bytes[i];
            dmx_idx++;

            if (dmx_idx >= (enderecoDMX + 7)) {
              if (raw_dmx_buf[0] == 0x00) {
                ultimoPacoteDMX = millis();
                int idx = enderecoDMX;

                brilhoCanais[0] = raw_dmx_buf[idx + 0];
                brilhoCanais[1] = raw_dmx_buf[idx + 1];
                brilhoCanais[2] = raw_dmx_buf[idx + 2];
                brilhoCanais[3] = raw_dmx_buf[idx + 3];
                brilhoGeral = raw_dmx_buf[idx + 4];
                velocidad = map(raw_dmx_buf[idx + 5], 0, 255, 0, 100);

                int dmxCH7 = raw_dmx_buf[idx + 6];
                if (dmxCH7 <= 50)        modoAtual = 0;
                else if (dmxCH7 <= 100)  modoAtual = 1;
                else if (dmxCH7 <= 150)  modoAtual = 2;
                else if (dmxCH7 <= 200)  modoAtual = 3;
                else                     modoAtual = 4;
              }
              dmx_em_frame = false;
            }
          }
        }
      }
    }
  }
}

void acordaTela() {
  tempoUltimaAtividade = millis();
  if (!telaAcesa) {
    oled.ssd1306_command(SSD1306_DISPLAYON);
    telaAcesa = true;
  }
}

void salvarConfiguracao() {
  preferences.begin("mileto_cfg", false);
  preferences.putInt("dmx", enderecoDMX);
  preferences.putInt("modo", modoAtual);
  preferences.putInt("vel", velocidad);
  preferences.putInt("dim", brilhoGeral);
  preferences.putInt("ch1", brilhoCanais[0]);
  preferences.putInt("ch2", brilhoCanais[1]);
  preferences.putInt("ch3", brilhoCanais[2]);
  preferences.putInt("ch4", brilhoCanais[3]);
  preferences.putInt("vch1", velocidadesCanais[0]);
  preferences.putInt("vch2", velocidadesCanais[1]);
  preferences.putInt("vch3", velocidadesCanais[2]);
  preferences.putInt("vch4", velocidadesCanais[3]);
  preferences.end();
}

void setRS485Direction(bool transmitir) {
  if (RS485_DIR_PIN == -1) return;
  if (transmitir) {
    digitalWrite(RS485_DIR_PIN, HIGH);
    delayMicroseconds(5);
  } else {
    uart_wait_tx_done(DMX_UART_NUM, portMAX_DELAY);
    digitalWrite(RS485_DIR_PIN, LOW);
  }
}

void executarVarreduraRDM() {
  if (!dispositivoConectado) return;

  // Sinaliza ao app o início da varredura RDM
  pTxCharacteristic->setValue("RDM_START\n");
  pTxCharacteristic->notify();
  delay(100);

  // Simulação conceitual de varredura RDM na linha (Pinos 20/21)
  // No mundo real, aqui você implementaria a máquina de estados DISC_UNIQUE_BRANCH
  // conforme a especificação ANSI E1.20 utilizando a serial half-duplex.

  // Enviando aparelhos fictícios identificados para validação na interface:
  pTxCharacteristic->setValue("RDM_DEV:4d49,00000101,1,7,SPOT_BEAM_200\n");
  pTxCharacteristic->notify();
  delay(100);

  pTxCharacteristic->setValue("RDM_DEV:4d49,00000102,8,4,PAR_LED_SLIM\n");
  pTxCharacteristic->notify();
  delay(100);

  pTxCharacteristic->setValue("RDM_DEV:2a2b,00005a90,12,12,STB_RGBW_PRO\n");
  pTxCharacteristic->notify();
  delay(100);

  pTxCharacteristic->setValue("RDM_END\n");
  pTxCharacteristic->notify();
}

void processarBluetooth() {
  acordaTela();
  int divisor = comandoPendente.indexOf(':');
  if (divisor == -1) return;

  String cmd = comandoPendente.substring(0, divisor);
  String val = comandoPendente.substring(divisor + 1);

  if (cmd == "SET_CH1")       brilhoCanais[0] = val.toInt();
  else if (cmd == "SET_CH2")  brilhoCanais[1] = val.toInt();
  else if (cmd == "SET_CH3")  brilhoCanais[2] = val.toInt();
  else if (cmd == "SET_CH4")  brilhoCanais[3] = val.toInt();
  else if (cmd == "SET_MODO") { modoAtual = min((int)val.toInt(), 4); }
  else if (cmd == "SET_VEL")  { velocidad = min((int)val.toInt(), 100); }
  else if (cmd == "SET_DIM")  brilhoGeral = val.toInt();
  else if (cmd == "VARREDURA_RDM") { executarVarreduraRDM(); }
  else if (cmd == "GRAVAR") {
    exibirTelaSalvando();
    salvarConfiguracao();
    delay(1000);
  }
  atualizarDisplay();
}

void atualizarDisplay() {
  if (!telaAcesa) return;
  oled.clearDisplay();
  oled.setCursor(0, 0);

  if (sistemaEmModoDMX) {
    oled.setTextSize(1);
    oled.print("MESA DMX: 7 CHs\n");
    oled.print(sinalDMXAtivo ? "STATUS: SINAL OK\n\n" : "STATUS: SEM SINAL\n\n");

    int porcDmx = map(brilhoGeral, 0, 255, 0, 100);
    oled.print("Brilho Geral\n");

    int totalBlocosDmx = 12;
    int preenchidosDmx = (porcDmx * totalBlocosDmx) / 100;
    for (int i = 0; i < totalBlocosDmx; i++) {
      if (i < preenchidosDmx) oled.print((char)219);
      else oled.print((char)176);
    }
    oled.print("\n\n");

    oled.setTextSize(2);
    oled.print("CH: ");
    oled.print(enderecoDMX);
  }
  else {
    int valorBrilhoAtual = 0;
    String nomeCampo = "";

    if (modoAtual == 0) {
      nomeCampo = "Brilho CH" + String(canalSelecionado + 1);
      valorBrilhoAtual = brilhoCanais[canalSelecionado];
    } else {
      nomeCampo = "Brilho " + String(nomesEfeitos[modoAtual]);
      valorBrilhoAtual = brilhoGeral;
    }

    int porcentagem = map(valorBrilhoAtual, 0, 255, 0, 100);

    oled.setTextSize(1);
    oled.print(nomeCampo);
    oled.print("\n\n");

    int totalBlocos = 12;
    int blocosPreenchidos = (porcentagem * totalBlocos) / 100;

    for (int i = 0; i < totalBlocos; i++) {
      if (i < blocosPreenchidos) oled.print((char)219);
      else oled.print((char)176);
    }
    oled.print("\n\n");

    oled.setTextSize(2);
    oled.print(porcentagem);
    oled.print("%");

    if (faseAtual == FASE_VALOR) {
      oled.setTextSize(1);
      oled.setCursor(110, 48);
      oled.print("[*]");
    }
  }
  oled.display();
}

void exibirTelaSalvando() {
  oled.clearDisplay();
  oled.setCursor(0, 0);

  oled.setTextSize(1);
  oled.print("Salvando\n");
  oled.print("Gravando...\n\n");

  for (int i = 0; i < 12; i++) oled.print((char)219);
  oled.print("\n\n");

  oled.setTextSize(2);
  oled.print("OK");
  oled.display();
}