#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// Driver nativo do ESP32 para UART
#include "driver/uart.h"
#include "soc/soc.h"

// --- INCLUSÃO DO BLE PARA ESP32 CORE 3.X ---
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "esp_gap_ble_api.h"

// --- INCLUSÃO DA LOGO ---
#include "MILETO_LOGO_1.h"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 oled(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

Preferences preferences;

// --- CONFIGURAÇÃO UART DMX512 (UART1 no C3) ---
#define DMX_UART_NUM UART_NUM_1
#define DMX_RX_PIN 20

static QueueHandle_t dmx_queue;
uint8_t raw_dmx_buf[515];
int dmx_idx = 0;
bool dmx_em_frame = false;

// --- UUIDs BLE (Nordic UART Service) ---
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
String comandoPendente = "";
bool novoComandoBle = false;

// --- MAPEAMENTO DE PINOS (C3 SUPER MINI) ---
#define MOSFET_CH1 0
#define MOSFET_CH2 1
#define MOSFET_CH3 5
#define MOSFET_CH4 4

#define BTN_MUDAR_CAMPO 6
#define BTN_FRENTE 7
#define BTN_VOLTA 10
#define BTN_GRAVAR 21
#define CHAVE_DMX_MANUAL 2

#define PWM_FREQ 4000
#define PWM_RES 8

#define OLED_SDA 8
#define OLED_SCL 9

// --- VARIÁVEIS DE ESTADO ---
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

// --- FUNÇÕES ---
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

// --- CALLBACKS BLE ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      dispositivoConectado = true;
    };
    void onDisconnect(BLEServer* pServer) {
      dispositivoConectado = false;
      BLEDevice::startAdvertising();
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue(); // RESOLVIDO: No Core 3.x agora retorna String
      if (rxValue.length() > 0) {
        comandoPendente = rxValue;
        novoComandoBle = true;
      }
    }
};

class MySecurityCallbacks : public BLESecurityCallbacks {
    uint32_t onPassKeyRequest() { return 123456; }
    void onPassKeyNotify(uint32_t pass_key) { Serial.printf("PIN: %d\n", pass_key); }
    bool onSecurityRequest() { return true; }
    void onAuthenticationComplete(esp_ble_auth_cmpl_t cmpl) {
      if (cmpl.success) Serial.println("Auth OK");
      else Serial.println("Auth Falhou");
    }
    bool onConfirmPIN(uint32_t pin) { return true; }
};

void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(BTN_MUDAR_CAMPO, INPUT_PULLUP);
  pinMode(BTN_FRENTE, INPUT_PULLUP);
  pinMode(BTN_VOLTA, INPUT_PULLUP);
  pinMode(BTN_GRAVAR, INPUT_PULLUP);
  pinMode(CHAVE_DMX_MANUAL, INPUT_PULLUP);

  ledcAttach(MOSFET_CH1, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH2, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH3, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH4, PWM_FREQ, PWM_RES);

  Wire.begin(OLED_SDA, OLED_SCL);
  delay(100);

  if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED ERR");
  }

  oled.setTextColor(SSD1306_WHITE);
  desenharLogo(MILETO_LOGO_1);
  delay(3000);

  preferences.begin("mileto_cfg", false);
  enderecoDMX = preferences.getInt("dmx", 1);
  modoAtual = preferences.getInt("modo", 0);
  velocidad = preferences.getInt("vel", 100);
  brilhoGeral = preferences.getInt("dim", 255);
  for (int i = 0; i < 4; i++) {
    char kCh[6], kV[7]; sprintf(kCh, "ch%d", i + 1); sprintf(kV, "vch%d", i + 1);
    brilhoCanais[i] = preferences.getInt(kCh, 255);
    velocidadesCanais[i] = preferences.getInt(kV, 100);
  }
  preferences.end();

  // --- CONFIGURAÇÃO BLE ---
  BLEDevice::init("MILETO"); // Nome para bater com o App original
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());
  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();

  // Segurança BLE modernizada para Core 3.x
  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setAuthenticationMode(ESP_LE_AUTH_REQ_SC_MITM_BOND);
  pSecurity->setCapability(ESP_IO_CAP_OUT);
  pSecurity->setInitEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  pSecurity->setStaticPIN(123456);
  BLEDevice::setSecurityCallbacks(new MySecurityCallbacks());

  pServer->getAdvertising()->start();

  // --- UART DMX ---
  uart_config_t uart_cfg = {
    .baud_rate = 250000, .data_bits = UART_DATA_8_BITS, .parity = UART_PARITY_DISABLE,
    .stop_bits = UART_STOP_BITS_2, .flow_ctrl = UART_HW_FLOWCTRL_DISABLE, .source_clk = UART_SCLK_DEFAULT
  };
  uart_param_config(DMX_UART_NUM, &uart_cfg);
  uart_set_pin(DMX_UART_NUM, UART_PIN_NO_CHANGE, DMX_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  uart_driver_install(DMX_UART_NUM, 1024, 0, 20, &dmx_queue, 0);

  tempoUltimaAtividade = millis();
  atualizarDisplay();
}

void loop() {
  static bool ultimoEstadoConexao = false;
  if (dispositivoConectado != ultimoEstadoConexao) {
    ultimoEstadoConexao = dispositivoConectado;
    acordaTela();
    if (dispositivoConectado) {
      pTxCharacteristic->setValue("CONNECTED_OK\n");
      pTxCharacteristic->notify();
    }
    atualizarDisplay();
  }

  if (novoComandoBle) {
    processarBluetooth();
    novoComandoBle = false;
    comandoPendente = "";
  }

  if (digitalRead(CHAVE_DMX_MANUAL) == LOW && millis() - ultimoDebounce >= 250) {
    ultimoDebounce = millis(); acordaTela();
    sistemaEmModoDMX = !sistemaEmModoDMX;
    if (!sistemaEmModoDMX) {
      preferences.begin("mileto_cfg", true);
      modoAtual = preferences.getInt("modo", 0); velocidad = preferences.getInt("vel", 100); brilhoGeral = preferences.getInt("dim", 255);
      for(int i=0; i<4; i++){
        char kC[6], kV[7]; sprintf(kC,"ch%d",i+1); sprintf(kV,"vch%d",i+1);
        brilhoCanais[i] = preferences.getInt(kC, 255); velocidadesCanais[i] = preferences.getInt(kV, 100);
      }
      preferences.end();
    }
    if (dispositivoConectado) {
      String msg = "CHAVE_MODO:"; msg += (sistemaEmModoDMX ? "DMX" : "RF"); msg += "\n";
      pTxCharacteristic->setValue(msg.c_str()); pTxCharacteristic->notify();
    }
    atualizarDisplay();
    while (digitalRead(CHAVE_DMX_MANUAL) == LOW) delay(10);
  }

  if (!sistemaEmModoDMX) {
    if (digitalRead(BTN_MUDAR_CAMPO) == LOW && millis() - ultimoDebounce >= 250) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_CAMPO) { faseAtual = FASE_MODO; linhaSelecionada = 0; }
      else if (faseAtual == FASE_VALOR) faseAtual = FASE_CAMPO;
      atualizarDisplay();
    }
    if (digitalRead(BTN_FRENTE) == LOW && millis() - ultimoDebounce >= 150) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_MODO) modoAtual = (modoAtual + 1) % 5;
      else if (faseAtual == FASE_CAMPO) linhaSelecionada = (linhaSelecionada == 1) ? 2 : 1;
      else if (faseAtual == FASE_VALOR) {
        if (linhaSelecionada == 1) {
          if (modoAtual == 0) canalSelecionado = (canalSelecionado + 1) % 4;
          else velocidad = min(velocidad + 5, 100);
        } else if (linhaSelecionada == 2) {
          if (modoAtual == 0) brilhoCanais[canalSelecionado] = min(brilhoCanais[canalSelecionado] + 15, 255);
          else brilhoGeral = min(brilhoGeral + 15, 255);
        }
      }
      atualizarDisplay();
    }
    if (digitalRead(BTN_VOLTA) == LOW && millis() - ultimoDebounce >= 150) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_MODO) modoAtual = (modoAtual <= 0) ? 4 : modoAtual - 1;
      else if (faseAtual == FASE_CAMPO) linhaSelecionada = (linhaSelecionada == 1) ? 2 : 1;
      else if (faseAtual == FASE_VALOR) {
        if (linhaSelecionada == 1) {
          if (modoAtual == 0) canalSelecionado = (canalSelecionado <= 0) ? 3 : canalSelecionado - 1;
          else velocidad = max(velocidad - 5, 0);
        } else if (linhaSelecionada == 2) {
          if (modoAtual == 0) brilhoCanais[canalSelecionado] = max(brilhoCanais[canalSelecionado] - 15, 0);
          else brilhoGeral = max(brilhoGeral - 15, 0);
        }
      }
      atualizarDisplay();
    }
    if (digitalRead(BTN_GRAVAR) == LOW && millis() - ultimoDebounce >= 250) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_MODO) { faseAtual = FASE_CAMPO; linhaSelecionada = 1; }
      else if (faseAtual == FASE_CAMPO) faseAtual = FASE_VALOR;
      else if (faseAtual == FASE_VALOR) {
        exibirTelaSalvando(); salvarConfiguracao(); delay(1000);
        faseAtual = FASE_MODO; linhaSelecionada = 0;
      }
      atualizarDisplay();
    }
  } else {
    if (digitalRead(BTN_FRENTE) == LOW && millis() - ultimoDebounce >= 150) {
      ultimoDebounce = millis(); acordaTela(); enderecoDMX = (enderecoDMX % 512) + 1; atualizarDisplay();
    }
    if (digitalRead(BTN_VOLTA) == LOW && millis() - ultimoDebounce >= 150) {
      ultimoDebounce = millis(); acordaTela(); enderecoDMX = (enderecoDMX <= 1) ? 512 : enderecoDMX - 1; atualizarDisplay();
    }
    if (digitalRead(BTN_GRAVAR) == LOW && millis() - ultimoDebounce >= 250) {
      ultimoDebounce = millis(); acordaTela(); exibirTelaSalvando(); salvarConfiguracao(); delay(1000); atualizarDisplay();
    }
  }

  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    oled.clearDisplay(); oled.display(); oled.ssd1306_command(SSD1306_DISPLAYOFF); telaAcesa = false;
  }
  if (sistemaEmModoDMX) processarMesaDMX();
  executarEfeitos();
}

void desenharLogo(const uint8_t* bitmap) {
  oled.clearDisplay(); oled.drawBitmap(0, 0, bitmap, 128, 64, SSD1306_WHITE); oled.display();
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
    pTxCharacteristic->setValue(payload.c_str()); pTxCharacteristic->notify();
  }
}

void executarEfeitos() {
  unsigned long tempo = millis();
  int d = map(velocidad, 0, 100, 800, 25);
  if (modoAtual == 0) {
    if (sistemaEmModoDMX) { for(int i=0; i<4; i++) writeChannel(i, (brilhoCanais[i] * brilhoGeral)/255); }
    else {
      static unsigned long ts[4] = {0,0,0,0}; static bool sts[4] = {0,0,0,0};
      for(int i=0; i<4; i++){
        if(velocidadesCanais[i] >= 100) sts[i] = 1;
        else {
          int dv = map(velocidadesCanais[i], 0, 99, 800, 40);
          if(tempo - ts[i] >= (unsigned long)dv){ ts[i] = tempo; sts[i] = !sts[i]; }
        }
        writeChannel(i, sts[i] ? (brilhoCanais[i]*brilhoGeral)/255 : 0);
      }
    }
  } else if (brilhoGeral == 0) { for(int i=0; i<4; i++) writeChannel(i, 0); }
  else {
    switch (modoAtual) {
      case 1: // FADE
        if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d / 12) {
          ultimaAtualizacaoEfeito = tempo; if (fadeDirection) fadeValue++; else fadeValue--;
          if (fadeValue >= 255) { fadeValue = 255; fadeDirection = false; } else if (fadeValue <= 0) { fadeValue = 0; fadeDirection = true; }
          writeChannel(0, (fadeValue * brilhoGeral) / 255); writeChannel(1, ((255 - fadeValue) * brilhoGeral) / 255);
          writeChannel(2, ((255 - fadeValue) * brilhoGeral) / 255); writeChannel(3, (fadeValue * brilhoGeral) / 255);
        } break;
      case 2: // STROBO
        if (velocidad >= 100) for(int i=0; i<4; i++) writeChannel(i, brilhoGeral);
        else if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d) {
          ultimaAtualizacaoEfeito = tempo; estadoStrobo = !estadoStrobo;
          int v = estadoStrobo ? brilhoGeral : 0; for(int i=0; i<4; i++) writeChannel(i, v);
        } break;
      case 3: // SEQUENC
        if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d) {
          ultimaAtualizacaoEfeito = tempo; passoAlternado = (passoAlternado + 1) % 4;
          for(int i=0; i<4; i++) writeChannel(i, (passoAlternado == i) ? brilhoGeral : 0);
        } break;
      case 4: for(int i=0; i<4; i++) writeChannel(i, brilhoGeral); break;
    }
  }
  enviarNiveisBT();
}

void processarMesaDMX() {
  uart_event_t evt;
  while (xQueueReceive(dmx_queue, (void*)&evt, 0)) {
    if (evt.type == UART_BREAK) { uart_flush_input(DMX_UART_NUM); dmx_idx = 0; dmx_em_frame = true; }
    else if (evt.type == UART_DATA && dmx_em_frame) {
      size_t l = 0; uart_get_buffered_data_len(DMX_UART_NUM, &l);
      if (l > 0) {
        uint8_t t[64]; int r = uart_read_bytes(DMX_UART_NUM, t, (l > 64) ? 64 : l, 0);
        for (int i = 0; i < r; i++) {
          if (dmx_em_frame) {
            if (dmx_idx < 515) raw_dmx_buf[dmx_idx] = t[i]; dmx_idx++;
            if (dmx_idx >= (enderecoDMX + 7)) {
              if (raw_dmx_buf[0] == 0x00) {
                ultimoPacoteDMX = millis(); sinalDMXAtivo = true; int idx = enderecoDMX;
                for(int c=0; c<4; c++) brilhoCanais[c] = raw_dmx_buf[idx+c];
                brilhoGeral = raw_dmx_buf[idx+4]; velocidad = map(raw_dmx_buf[idx+5], 0, 255, 0, 100);
                int m = raw_dmx_buf[idx+6];
                if (m <= 50) modoAtual = 0; else if (m <= 100) modoAtual = 1;
                else if (m <= 150) modoAtual = 2; else if (m <= 200) modoAtual = 3; else modoAtual = 4;
              }
              dmx_em_frame = false;
            }
          }
        }
      }
    }
  }
}

void processarBluetooth() {
  acordaTela();
  comandoPendente.replace("\n", ""); comandoPendente.replace("\r", ""); comandoPendente.trim();
  int div = comandoPendente.indexOf(':'); if (div == -1) return;
  String cmd = comandoPendente.substring(0, div); String val = comandoPendente.substring(div + 1);
  int iv = val.toInt();
  if (cmd == "GET_CAPABILITIES") { pTxCharacteristic->setValue("CAPS:MANUAL,FADE,STROBO,SEQUENC,FIXO\n"); pTxCharacteristic->notify(); return; }
  if (cmd == "SET_CH1") brilhoCanais[0] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_CH2") brilhoCanais[1] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_CH3") brilhoCanais[2] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_CH4") brilhoCanais[3] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_VCH1") velocidadesCanais[0] = iv;
  else if (cmd == "SET_VCH2") velocidadesCanais[1] = iv;
  else if (cmd == "SET_VCH3") velocidadesCanais[2] = iv;
  else if (cmd == "SET_VCH4") velocidadesCanais[3] = iv;
  else if (cmd == "SET_MODO") { modoAtual = min(iv, 4); }
  else if (cmd == "SET_VEL") { velocidad = min(iv, 100); }
  else if (cmd == "SET_DIM") { brilhoGeral = map(iv, 0, 100, 0, 255); }
  else if (cmd == "SET_DMX") { enderecoDMX = iv; }
  else if (cmd == "CHAVE_MODO") { sistemaEmModoDMX = (val == "DMX"); }
  else if (cmd == "GRAVAR") { exibirTelaSalvando(); salvarConfiguracao(); pTxCharacteristic->setValue("GRAVAR:OK\n"); pTxCharacteristic->notify(); delay(1000); }
  atualizarDisplay();
}

void acordaTela() { tempoUltimaAtividade = millis(); if (!telaAcesa) { oled.ssd1306_command(SSD1306_DISPLAYON); telaAcesa = true; } }

void salvarConfiguracao() {
  preferences.begin("mileto_cfg", false);
  preferences.putInt("dmx", enderecoDMX); preferences.putInt("modo", modoAtual);
  preferences.putInt("vel", velocidad); preferences.putInt("dim", brilhoGeral);
  for (int i = 0; i < 4; i++) { char kC[6], kV[7]; sprintf(kC,"ch%d",i+1); sprintf(kV,"vch%d",i+1); preferences.putInt(kC, brilhoCanais[i]); preferences.putInt(kV, velocidadesCanais[i]); }
  preferences.end();
}

void atualizarDisplay() {
  if (!telaAcesa) return;
  oled.clearDisplay(); oled.setTextSize(1);
  if (sistemaEmModoDMX) {
    oled.setCursor(0, 0); oled.print("MESA DMX: 7 CHs");
    oled.setCursor(0, 15); oled.print("STATUS: "); oled.print(sinalDMXAtivo ? "OK" : "OFF");
    int porc = map(brilhoGeral, 0, 255, 0, 100);
    oled.setCursor(0, 30); oled.print("Brilho Geral");
    oled.setCursor(0, 42); for (int i = 0; i < 12; i++) oled.print(i < (porc * 12) / 100 ? (char)219 : (char)176);
    oled.setCursor(85, 48); oled.setTextSize(2); oled.print(enderecoDMX);
  } else {
    int v = (modoAtual == 0) ? brilhoCanais[canalSelecionado] : brilhoGeral;
    int p = map(v, 0, 255, 0, 100);
    oled.setCursor(0, 0); oled.print(dispositivoConectado ? "* APP ATIVO *" : "--- MANUAL ---");
    oled.setCursor(0, 12); oled.print((modoAtual == 0) ? "Brilho CH" : "Brilho "); if(modoAtual == 0) oled.print(canalSelecionado + 1); else oled.print(nomesEfeitos[modoAtual]);
    oled.setCursor(0, 26); for (int i = 0; i < 12; i++) oled.print(i < (p * 12) / 100 ? (char)219 : (char)176);
    oled.setCursor(0, 44); oled.setTextSize(2); oled.print(p); oled.print("%");
    if (faseAtual == FASE_VALOR) { oled.setCursor(110, 48); oled.setTextSize(1); oled.print("[*]"); }
  }
  oled.display();
}

void exibirTelaSalvando() {
  oled.clearDisplay(); oled.setCursor(0, 0); oled.setTextSize(1); oled.print("Salvando\nGravando...\n\n");
  for (int i = 0; i < 12; i++) oled.print((char)219);
  oled.setCursor(0, 44); oled.setTextSize(2); oled.print("OK"); oled.display();
}
