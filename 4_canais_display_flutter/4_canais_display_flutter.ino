#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// Driver nativo do ESP32 para UART
#include "driver/uart.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// --- BIBLIOTECAS BLE (NIMBLE PARA C3) ---
#include <NimBLEDevice.h>

// --- INCLUSÃO DA LOGO ---
#include "MILETO_LOGO_1.h"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 oled(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

Preferences preferences;

// --- CONFIGURAÇÃO UART DMX512 ---
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

NimBLEServer *pServer = NULL;
NimBLECharacteristic *pTxCharacteristic;
String comandoPendente = "";
bool novoComandoBle = false;

// --- MAPEAMENTO DE PINOS (C3 SUPER MINI) ---
// MOSFETs (PWM)
#define MOSFET_CH1 0
#define MOSFET_CH2 1
#define MOSFET_CH3 5
#define MOSFET_CH4 4

// --- NOVO SISTEMA: ENCODER ROTATIVO ---
#define ENC_CLK 6    // Clock do Encoder
#define ENC_DT  7    // Data do Encoder
#define ENC_SW  10   // Botão de Confirmação (Click)
#define CHAVE_DMX_MANUAL 3  // Botão separado para alternar modo

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

// --- VARIÁVEIS DO ENCODER ---
int lastClkState;

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
void lidarComEncoder();

// --- CALLBACKS BLE ---
class MyServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) override {
      dispositivoConectado = true;
    };
    void onDisconnect(NimBLEServer* pServer) override {
      dispositivoConectado = false;
      NimBLEDevice::startAdvertising();
    }
};

class MyCallbacks: public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *pCharacteristic) override {
      String rxValue = pCharacteristic.getValue();
      if (rxValue.length() > 0) {
        comandoPendente = rxValue;
        novoComandoBle = true;
      }
    }
};

void setup() {
#ifdef RTC_CNTL_BROWN_OUT_REG
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
#endif
  Serial.begin(115200);
  delay(1000);

  // Configuração do Encoder
  pinMode(ENC_CLK, INPUT_PULLUP);
  pinMode(ENC_DT, INPUT_PULLUP);
  pinMode(ENC_SW, INPUT_PULLUP);
  pinMode(CHAVE_DMX_MANUAL, INPUT_PULLUP);

  lastClkState = digitalRead(ENC_CLK);

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

  // Carrega configurações persistentes
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

  // --- CONFIGURAÇÃO BLE (NIMBLE) ---
  NimBLEDevice::init("MILETO");
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic *pRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, NIMBLE_PROPERTY::WRITE);
  pRxCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->start();

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
  // Handshake e Segurança MILETO
  static bool ultimoEstadoConexao = false;
  if (dispositivoConectado != ultimoEstadoConexao) {
    ultimoEstadoConexao = dispositivoConectado;
    acordaTela();
    if (dispositivoConectado) {
      // --- AUTENTICAÇÃO PRODUTO MILETO ---
      // O App agora espera este código para liberar o uso
      pTxCharacteristic->setValue("MILETO_AUTH:VALID\nCONNECTED_OK\n");
      pTxCharacteristic->notify();
    }
    atualizarDisplay();
  }

  if (novoComandoBle) {
    processarBluetooth();
    novoComandoBle = false;
    comandoPendente = "";
  }

  // Lidar com o Encoder Rotativo
  lidarComEncoder();

  // Troca de Modo DMX/Manual via Botão
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

  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    oled.clearDisplay(); oled.display(); oled.ssd1306_command(SSD1306_DISPLAYOFF); telaAcesa = false;
  }
  if (sistemaEmModoDMX) processarMesaDMX();
  executarEfeitos();
}

void lidarComEncoder() {
  int currentClkState = digitalRead(ENC_CLK);

  // Detecta Rotação
  if (currentClkState != lastClkState && currentClkState == LOW) {
    acordaTela();
    bool subindo = digitalRead(ENC_DT) != currentClkState;

    if (!sistemaEmModoDMX) {
      if (faseAtual == FASE_MODO) {
        if (subindo) modoAtual = (modoAtual + 1) % 5;
        else modoAtual = (modoAtual <= 0) ? 4 : modoAtual - 1;
      }
      else if (faseAtual == FASE_CAMPO) {
        int maxLinhas = (modoAtual == 0) ? 3 : 2;
        if (subindo) linhaSelecionada = (linhaSelecionada % maxLinhas) + 1;
        else linhaSelecionada = (linhaSelecionada <= 1) ? maxLinhas : linhaSelecionada - 1;
      }
      else if (faseAtual == FASE_VALOR) {
        if (linhaSelecionada == 1) {
          if (modoAtual == 0) {
            if (subindo) canalSelecionado = (canalSelecionado + 1) % 4;
            else canalSelecionado = (canalSelecionado <= 0) ? 3 : canalSelecionado - 1;
          } else {
            if (subindo) velocidad = min(velocidad + 5, 100);
            else velocidad = max(velocidad - 5, 0);
          }
        } else if (linhaSelecionada == 2) {
          if (modoAtual == 0) {
            if (subindo) brilhoCanais[canalSelecionado] = min(brilhoCanais[canalSelecionado] + 15, 255);
            else brilhoCanais[canalSelecionado] = max(brilhoCanais[canalSelecionado] - 15, 0);
          } else {
            if (subindo) brilhoGeral = min(brilhoGeral + 15, 255);
            else brilhoGeral = max(brilhoGeral - 15, 0);
          }
        } else if (linhaSelecionada == 3 && modoAtual == 0) {
          if (subindo) velocidadesCanais[canalSelecionado] = min(velocidadesCanais[canalSelecionado] + 5, 100);
          else velocidadesCanais[canalSelecionado] = max(velocidadesCanais[canalSelecionado] - 5, 0);
        }
      }
    } else {
      // Modo DMX - Ajuste do endereço
      if (subindo) enderecoDMX = (enderecoDMX >= 512) ? 1 : enderecoDMX + 1;
      else enderecoDMX = (enderecoDMX <= 1) ? 512 : enderecoDMX - 1;
    }
    atualizarDisplay();
  }
  lastClkState = currentClkState;

  // Detecta Click (SW)
  if (digitalRead(ENC_SW) == LOW && millis() - ultimoDebounce >= 300) {
    ultimoDebounce = millis();
    acordaTela();

    if (!sistemaEmModoDMX) {
      if (faseAtual == FASE_MODO) { faseAtual = FASE_CAMPO; linhaSelecionada = 1; }
      else if (faseAtual == FASE_CAMPO) { faseAtual = FASE_VALOR; }
      else if (faseAtual == FASE_VALOR) {
        exibirTelaSalvando();
        salvarConfiguracao();
        delay(800);
        faseAtual = FASE_MODO;
        linhaSelecionada = 0;
      }
    } else {
      exibirTelaSalvando();
      salvarConfiguracao();
      delay(800);
    }
    atualizarDisplay();
  }
}

void desenharLogo(const uint8_t* bitmap) {
  oled.clearDisplay();
  uint8_t *buffer = oled.getBuffer();
  for (int i = 0; i < 1024; i++) {
    buffer[i] = pgm_read_byte(&bitmap[i]);
  }
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
  else if (cmd == "EFEITO_PISTA") { if(val=="START") modoAtual=3; else modoAtual=0; }
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
    oled.setCursor(0, 0); oled.print(dispositivoConectado ? "* APP ATIVO *" : "--- MANUAL ---");
    if (modoAtual == 0) {
      oled.setCursor(0, 10); oled.print("CH:"); oled.print(canalSelecionado + 1);
      if(faseAtual != FASE_MODO && linhaSelecionada == 1) oled.print(" <");

      int b = map(brilhoCanais[canalSelecionado], 0, 255, 0, 100);
      oled.setCursor(0, 20); oled.print("B:"); oled.print(b); oled.print("%");
      if(faseAtual != FASE_MODO && linhaSelecionada == 2) oled.print(" <");
      oled.setCursor(50, 20); for (int i = 0; i < 10; i++) oled.print(i < (b * 10) / 100 ? (char)219 : (char)176);

      int s = velocidadesCanais[canalSelecionado];
      oled.setCursor(0, 30); oled.print("V:"); oled.print(s); oled.print("%");
      if(faseAtual != FASE_MODO && linhaSelecionada == 3) oled.print(" <");
      oled.setCursor(50, 30); for (int i = 0; i < 10; i++) oled.print(i < (s * 10) / 100 ? (char)219 : (char)176);

      oled.setCursor(0, 45); oled.print("MODO: "); oled.print(nomesEfeitos[modoAtual]);
    } else {
      int p = map(brilhoGeral, 0, 255, 0, 100);
      oled.setCursor(0, 12); oled.print("Efeito: "); oled.print(nomesEfeitos[modoAtual]);
      if(faseAtual != FASE_MODO && linhaSelecionada == 1) oled.print(" <");
      oled.setCursor(0, 26); for (int i = 0; i < 12; i++) oled.print(i < (p * 12) / 100 ? (char)219 : (char)176);
      oled.setCursor(0, 44); oled.setTextSize(2); oled.print(p); oled.print("%");
    }
    if (faseAtual == FASE_VALOR) { oled.setCursor(110, 48); oled.setTextSize(1); oled.print("[*]"); }
  }
  oled.display();
}

void exibirTelaSalvando() {
  oled.clearDisplay(); oled.setCursor(0, 0); oled.setTextSize(1); oled.print("Salvando\nGravando...\n\n");
  for (int i = 0; i < 12; i++) oled.print((char)219);
  oled.setCursor(0, 44); oled.setTextSize(2); oled.print("OK"); oled.display();
}
