#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// Driver nativo do ESP32 para UART (Configurado para UART1 no C3)
#include "driver/uart.h"

// Bibliotecas nativas do ESP32 para controle de estabilidade de hardware
#include "soc/soc.h"

// --- INCLUSÃO DAS BIBLIOTECAS BLE ---
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

// --- CONFIGURAÇÃO DA UART NATIVA PARA DMX512 ---
#define DMX_UART_NUM UART_NUM_1  // Ajustado para UART1 (O C3 não possui UART2)
#define DMX_RX_PIN 20            // Pino RX conectado ao MAX485

static QueueHandle_t dmx_queue;
uint8_t raw_dmx_buf[515];
int dmx_idx = 0;
bool dmx_em_frame = false;

// --- CONFIGURAÇÃO UUIDs BLE (Nordic UART Padrão) ---
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
String comandoPendente = "";
bool novoComandoBle = false;

// --- MAPEAMENTO DE PINOS DOS MOSFETS (Ajustado para o C3 SuperMini) ---
#define MOSFET_CH1 0
#define MOSFET_CH2 1
#define MOSFET_CH3 5             // Movido para o GPIO 5 (Livre de Strapping e com PWM)
#define MOSFET_CH4 4

// Painel de Controle Físico (Pinos mapeados para as laterais da placa)
#define BTN_MUDAR_CAMPO 6   // Botão 1: VOLTAR / CANCELAR
#define BTN_FRENTE 7        // Botão 2: Sobe / Mais (+)
#define BTN_VOLTA 10        // Botão 3: Desce / Menos (-)
#define BTN_GRAVAR 21       // Botão 4: Avançar / OK (Pino físico traseiro)
#define CHAVE_DMX_MANUAL 2  // Botão de Pulso: Alterna Modo

#define PWM_FREQ 4000
#define PWM_RES 8

// --- DISPLAY OLED NATIVO ---
#define OLED_SDA 8
#define OLED_SCL 9

// --- VARIÁVEIS DE CONTROLE DOS ESTÁGIOS DO MENU ---
enum FasesMenu { FASE_MODO,
                 FASE_CAMPO,
                 FASE_VALOR };
FasesMenu faseAtual = FASE_MODO;

// --- VARIÁVEIS DE CONFIGURAÇÃO ---
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

// --- DECLARAÇÃO DE FUNÇÕES ---
void atualizarDisplay();
void acordaTela();
void executarEfeitos();
void writeChannel(int ch, int val);
void enviarNiveisBT();
void processarMesaDMX();
void salvarConfiguracao();
void desenharLogo(const uint8_t* bitmap);
void processarBluetooth();
void exibirTelaSalvando();

// --- CALLBACKS DO SERVIDOR BLE ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      dispositivoConectado = true;
    };
    void onDisconnect(BLEServer* pServer) {
      dispositivoConectado = false;
      pServer->getAdvertising()->start(); // Reinicia a transmissão para reconexão automática
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) {
        comandoPendente = String(rxValue.c_str());
        novoComandoBle = true;
      }
    }
};

// --- CALLBACK DE SEGURANÇA PARA SOLICITAÇÃO E VALIDAÇÃO DO PIN ---
class MySecurityCallbacks : public BLESecurityCallbacks {
    uint32_t onPassKeyRequest() {
        return 123456; // Senha numérico enviada ao pareamento pareado por hardware
    }
    void onPassKeyNotify(uint32_t pass_key) {}
    bool onSecurityRequest() { return true; }
    bool onAuthenticationComplete(esp_ble_auth_cmpl_t cmpl) {
        if (cmpl.success) {
            Serial.println("Autenticacao BLE efetuada com sucesso!");
            return true;
        } else {
            Serial.println("Erro na autenticacao BLE. Senha incorreta.");
            return false;
        }
    }
};

void setup() {
  Serial.begin(115200);
  delay(1000); // Janela para estabilização de energia da placa
  Serial.println("\n====================================");
  Serial.println("   MILETO - FIRMWARE ESP32 C3 V5.4   ");
  Serial.println("====================================");

  // Inicializa os Pinos de Controle Físico
  pinMode(BTN_MUDAR_CAMPO, INPUT_PULLUP);
  pinMode(BTN_FRENTE, INPUT_PULLUP);
  pinMode(BTN_VOLTA, INPUT_PULLUP);
  pinMode(BTN_GRAVAR, INPUT_PULLUP);
  pinMode(CHAVE_DMX_MANUAL, INPUT_PULLUP);

  // Ativa PWM em todos os 4 canais de MOSFET
  ledcAttach(MOSFET_CH1, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH2, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH3, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH4, PWM_FREQ, PWM_RES);

  // Inicializa I2C
  Wire.begin(OLED_SDA, OLED_SCL);
  delay(100);

  // Inicializa OLED com Adafruit
  if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("ERRO OLED!");
  }
  oled.setTextColor(SSD1306_WHITE);

  // --- EXIBE A LOGO ---
  desenharLogo(MILETO_LOGO_1);
  delay(3000);

  // Carrega configurações da Flash NVS
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

  // --- INICIALIZAÇÃO DO BLE (NORDIC UART COM PARAMETROS DE CRIPTOGRAFIA) ---
  BLEDevice::init("MILETO_C3");

  // Configurações de autenticação obrigatória (MITM)
  BLEDevice::setEncryptionLevel(ESP_BLE_SEC_ENCRYPT_MITM);
  BLEDevice::setSecurityCallbacks(new MySecurityCallbacks());

  // Registra a senha de pareamento direto na Stack GAP
  uint32_t passkey = 123456;
  esp_ble_gap_set_security_param(ESP_BLE_SM_SET_STATIC_PASSKEY, &passkey, sizeof(uint32_t));

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
  pServer->getAdvertising()->start();
  Serial.println("Servico BLE UART Inicializado.");

  // --- CONFIGURAÇÃO DA UART NATIVA (DMX512: 250kbps, 8N2) ---
  uart_config_t uart_config = {
    .baud_rate = 250000,
    .data_bits = UART_DATA_8_BITS,
    .parity = UART_PARITY_DISABLE,
    .stop_bits = UART_STOP_BITS_2,
    .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
    .source_clk = UART_SCLK_DEFAULT
  };
  uart_param_config(DMX_UART_NUM, &uart_config);
  uart_set_pin(DMX_UART_NUM, UART_PIN_NO_CHANGE, DMX_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  uart_driver_install(DMX_UART_NUM, 1024, 0, 20, &dmx_queue, 0);

  tempoUltimaAtividade = millis();
  atualizarDisplay();
}

void loop() {
  // --- GERENCIADOR DE SINAL BLE ---
  static bool ultimoEstadoConexao = false;
  if (dispositivoConectado != ultimoEstadoConexao) {
    ultimoEstadoConexao = dispositivoConectado;
    acordaTela();
    atualizarDisplay();
  }

  // --- PROCESSAMENTO SEGURO DE COMANDOS APP (BLE) ---
  if (novoComandoBle) {
    processarBluetooth();
    novoComandoBle = false;
    comandoPendente = "";
  }

  // --- LÓGICA DO BOTÃO DMX (BOTÃO DE PULSO ALTERNADOR) ---
  if (digitalRead(CHAVE_DMX_MANUAL) == LOW) {
    delay(50);
    if (digitalRead(CHAVE_DMX_MANUAL) == LOW) {
      if (millis() - ultimoDebounce >= 250) {
        ultimoDebounce = millis();
        acordaTela();

        sistemaEmModoDMX = !sistemaEmModoDMX;

        // Ao sair do modo DMX, restaura configurações salvas
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

        if (dispositivoConectado) {
          String msg = "CHAVE_MODO:";
          msg += (sistemaEmModoDMX ? "DMX" : "RF");
          msg += "\n";
          pTxCharacteristic->setValue(msg.c_str());
          pTxCharacteristic->notify();
        }

        atualizarDisplay();
        while (digitalRead(CHAVE_DMX_MANUAL) == LOW) { delay(10); }
      }
    }
  }

  // --- CONTROLE DOS BOTÕES DO MENU (MODO MANUAL) ---
  if (!sistemaEmModoDMX) {

    // BOTÃO 1 (BTN_MUDAR_CAMPO): Função "VOLTAR"
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

    // BOTÃO 2 (BTN_FRENTE): SOBE / INCREMENTAR (+)
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
              if (modoAtual == 0) {
                canalSelecionado = (canalSelecionado + 1) % 4;
              } else {
                velocidad += 5;
                if (velocidad > 100) velocidad = 100;
              }
            } else if (linhaSelecionada == 2) {
              if (modoAtual == 0) {
                brilhoCanais[canalSelecionado] = min(brilhoCanais[canalSelecionado] + 15, 255);
              } else {
                brilhoGeral = min(brilhoGeral + 15, 255);
              }
            }
          }

          atualizarDisplay();
          while (digitalRead(BTN_FRENTE) == LOW) { delay(10); }
        }
      }
    }

    // BOTÃO 3 (BTN_VOLTA): DESCE / DECREMENTAR (-)
    if (digitalRead(BTN_VOLTA) == LOW) {
      delay(50);
      if (digitalRead(BTN_VOLTA) == LOW) {
        if (millis() - ultimoDebounce >= 150) {
          ultimoDebounce = millis();
          acordaTela();

          if (faseAtual == FASE_MODO) {
            modoAtual--;
            if (modoAtual < 0) modoAtual = 4;
          } else if (faseAtual == FASE_CAMPO) {
            linhaSelecionada = (linhaSelecionada == 1) ? 2 : 1;
          } else if (faseAtual == FASE_VALOR) {
            if (linhaSelecionada == 1) {
              if (modoAtual == 0) {
                canalSelecionado--;
                if (canalSelecionado < 0) canalSelecionado = 3;
              } else {
                velocidad -= 5;
                if (velocidad < 0) velocidad = 0;
              }
            } else if (linhaSelecionada == 2) {
              if (modoAtual == 0) {
                brilhoCanais[canalSelecionado] = max(brilhoCanais[canalSelecionado] - 15, 0);
              } else {
                brilhoGeral = max(brilhoGeral - 15, 0);
              }
            }
          }

          atualizarDisplay();
          while (digitalRead(BTN_VOLTA) == LOW) { delay(10); }
        }
      }
    }

    // BOTÃO 4 (BTN_GRAVAR): CONFIRMAR / OK
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
  }
  // --- CONTROLE DOS BOTÕES NO MODO DMX ---
  else {
    if (digitalRead(BTN_FRENTE) == LOW) {
      delay(50);
      if (digitalRead(BTN_FRENTE) == LOW) {
        if (millis() - ultimoDebounce >= 150) {
          ultimoDebounce = millis();
          acordaTela();
          enderecoDMX++;
          if (enderecoDMX > 512) enderecoDMX = 1;
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
          enderecoDMX--;
          if (enderecoDMX < 1) enderecoDMX = 512;
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

  // --- ECONOMIA DE TELA ---
  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    oled.clearDisplay();
    oled.display();
    oled.ssd1306_command(SSD1306_DISPLAYOFF);
    telaAcesa = false;
  }

  if (sistemaEmModoDMX) {
    processarMesaDMX();
  }

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

void enviarNiveisBT() {
  static unsigned long last = 0;
  if (dispositivoConectado && millis() - last >= 60) {
    last = millis();
    String payload = "CH_LEVELS:";
    for(int i=0; i<4; i++){
      payload += String(map(niveisAtuais[i], 0, 255, 0, 100));
      if(i<3) payload += ",";
    }
    payload += "\n";
    pTxCharacteristic->setValue(payload.c_str());
    pTxCharacteristic->notify();
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
    }
    else {
      static unsigned long ultimosTempos[4] = {0, 0, 0, 0};
      static boolean estadosCanais[4] = {false, false, false, false};
      int delaysIndividuais[4];

      for (int i = 0; i < 4; i++) {
        if (velocidadesCanais[i] >= 100) {
          delaysIndividuais[i] = 0;
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
    enviarNiveisBT();
    return;
  }

  if (brilhoGeral == 0) {
    writeChannel(0, 0);
    writeChannel(1, 0);
    writeChannel(2, 0);
    writeChannel(3, 0);
    enviarNiveisBT();
    return;
  }

  switch (modoAtual) {
    case 1:
      if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito / 12) {
        ultimaAtualizacaoEfeito = tempoAtual;
        if (fadeDirection) fadeValue++; else fadeValue--;
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
        writeChannel(0, brilhoGeral);
        writeChannel(1, brilhoGeral);
        writeChannel(2, brilhoGeral);
        writeChannel(3, brilhoGeral);
      }
      else {
        if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito) {
          ultimaAtualizacaoEfeito = tempoAtual;
          estadoStrobo = !estadoStrobo;
          int intensidad = estadoStrobo ? brilhoGeral : 0;
          writeChannel(0, intensidad);
          writeChannel(1, intensidad);
          writeChannel(2, intensidad);
          writeChannel(3, intensidad);
        }
      }
      break;

    case 3:
      if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito) {
        ultimaAtualizacaoEfeito = tempoAtual;
        passoAlternado = (passoAlternado + 1) % 4;
        writeChannel(0, (passoAlternado == 0) ? brilhoGeral : 0);
        writeChannel(1, (passoAlternado == 1) ? brilhoGeral : 0);
        writeChannel(2, (passoAlternado == 2) ? brilhoGeral : 0);
        writeChannel(3, (passoAlternado == 3) ? brilhoGeral : 0);
      }
      break;

    case 4:
      writeChannel(0, brilhoGeral);
      writeChannel(1, brilhoGeral);
      writeChannel(2, brilhoGeral);
      writeChannel(3, brilhoGeral);
      break;
  }
  enviarNiveisBT();
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
            if (dmx_idx < 515) {
              raw_dmx_buf[dmx_idx] = temp_bytes[i];
            }
            dmx_idx++;

            if (dmx_idx >= (enderecoDMX + 7)) {
              if (raw_dmx_buf[0] == 0x00) {
                ultimoPacoteDMX = millis();
                sinalDMXAtivo = true;

                int idx = enderecoDMX;
                int dmxCH1 = raw_dmx_buf[idx + 0];
                int dmxCH2 = raw_dmx_buf[idx + 1];
                int dmxCH3 = raw_dmx_buf[idx + 2];
                int dmxCH4 = raw_dmx_buf[idx + 3];
                int dmxCH5 = raw_dmx_buf[idx + 4];
                int dmxCH6 = raw_dmx_buf[idx + 5];
                int dmxCH7 = raw_dmx_buf[idx + 6];

                brilhoGeral = dmxCH5;
                velocidad = map(dmxCH6, 0, 255, 0, 100);

                brilhoCanais[0] = dmxCH1;
                brilhoCanais[1] = dmxCH2;
                brilhoCanais[2] = dmxCH3;
                brilhoCanais[3] = dmxCH4;

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

void processarBluetooth() {
  acordaTela();
  int divisor = comandoPendente.indexOf(':');
  if (divisor == -1) return;

  String cmd = comandoPendente.substring(0, divisor);
  String val = comandoPendente.substring(divisor + 1);
  int intVal = val.toInt();

  if (cmd == "SET_CH1") { brilhoCanais[0] = map(intVal, 0, 100, 0, 255); }
  else if (cmd == "SET_CH2") { brilhoCanais[1] = map(intVal, 0, 100, 0, 255); }
  else if (cmd == "SET_CH3") { brilhoCanais[2] = map(intVal, 0, 100, 0, 255); }
  else if (cmd == "SET_CH4") { brilhoCanais[3] = map(intVal, 0, 100, 0, 255); }
  else if (cmd == "SET_VCH1") { velocidadesCanais[0] = intVal; }
  else if (cmd == "SET_VCH2") { velocidadesCanais[1] = intVal; }
  else if (cmd == "SET_VCH3") { velocidadesCanais[2] = intVal; }
  else if (cmd == "SET_VCH4") { velocidadesCanais[3] = intVal; }
  else if (cmd == "SET_MODO") { modoAtual = intVal; if (modoAtual > 4) modoAtual = 4; }
  else if (cmd == "SET_VEL") { velocidad = intVal; if (velocidad > 100) velocidad = 100; }
  else if (cmd == "SET_DIM") { brilhoGeral = map(intVal, 0, 100, 0, 255); }
  else if (cmd == "GRAVAR") { exibirTelaSalvando(); salvarConfiguracao(); delay(1000); }
  else if (cmd == "CHAVE_MODO") { sistemaEmModoDMX = (val == "DMX"); }
  else if (cmd == "GET_CAPABILITIES") {
    String cap = "CAPS:MANUAL,FADE,STROBO,SEQUENC,FIXO\n";
    pTxCharacteristic->setValue(cap.c_str());
    pTxCharacteristic->notify();
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
    int preenchidosDmx = (porcDmx * 12) / 100;
    for (int i = 0; i < 12; i++) oled.print(i < preenchidosDmx ? (char)219 : (char)176);
    oled.print("\n\n"); oled.setTextSize(2); oled.print("CH: "); oled.print(enderecoDMX);
  }
  else {
    int valorBrilhoAtual = 0; String nomeCampo = "";
    if (modoAtual == 0) { nomeCampo = "Brilho CH" + String(canalSelecionado + 1); valorBrilhoAtual = brilhoCanais[canalSelecionado]; }
    else { nomeCampo = "Brilho " + String(nomesEfeitos[modoAtual]); valorBrilhoAtual = brilhoGeral; }
    int porcentagem = map(valorBrilhoAtual, 0, 255, 0, 100);
    oled.setTextSize(1); oled.print(nomeCampo); oled.print("\n\n");
    int preenchidos = (porcentagem * 12) / 100;
    for (int i = 0; i < 12; i++) oled.print(i < preenchidos ? (char)219 : (char)176);
    oled.print("\n\n"); oled.setTextSize(2); oled.print(porcentagem); oled.print("%");
    if (faseAtual == FASE_VALOR) { oled.setTextSize(1); oled.setCursor(110, 48); oled.print("[*]"); }
  }
  oled.display();
}

void exibirTelaSalvando() {
  oled.clearDisplay(); oled.setCursor(0, 0); oled.setTextSize(1);
  oled.print("Salvando\nGravando...\n\n");
  for (int i = 0; i < 12; i++) oled.print((char)219);
  oled.print("\n\n"); oled.setTextSize(2); oled.print("OK"); oled.display();
}
