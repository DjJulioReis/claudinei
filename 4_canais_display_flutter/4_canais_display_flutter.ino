#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Preferences.h>

// --- INCLUDES SOLICITADOS ---
#include "driver/uart.h"
#include "soc/uart_struct.h"
#include "freertos/queue.h"
#include "soc/rtc_cntl_reg.h"
#include <NimBLEDevice.h>
#include "MILETO_LOGO_1.h"

#define LARGURA_TELA 128
#define ALTURA_TELA 64
#define OLED_RESET -1
Adafruit_SSD1306 display(LARGURA_TELA, ALTURA_TELA, &Wire, OLED_RESET);

#define ENC_CLK 6
#define ENC_DT   7
#define ENC_SW  10

#define MOSFET_CH1 0
#define MOSFET_CH2 1
#define MOSFET_CH3 5
#define MOSFET_CH4 4

#define PWM_FREQ 4000
#define PWM_RES 8

#define DMX_UART_NUM UART_NUM_1
#define DMX_RX_PIN 20
#define DMX_TX_PIN 21
#define RS485_DIR_PIN 3  // Controle de direção física para DE/RE RDM

static QueueHandle_t dmx_queue;
uint8_t raw_dmx_buf[520];
int dmx_idx = 0;
bool dmx_em_frame = false;

enum FasesMenu { FASE_MODO, FASE_CAMPO, FASE_VALOR };
FasesMenu faseAtual = FASE_MODO;

// --- VARIÁVEIS DE ESTADO ---
bool sistemaEmModoDMX = false; // Estado Mestre
int modoAtual = 1;            // Efeito Selecionado (1 a 5)
int modoDMXTemp = 1;          // Efeito vindo da Mesa DMX

int linhaSelecionada = 1;
int canalSelecionado = 0;
int enderecoDMX = 1;
int velocidad = 50;
int brilhoGeral = 255;

int brilhoCanais[4] = {255, 255, 255, 255};
int velocidadesCanais[4] = {100, 100, 100, 100};
int niveisAtuais[4] = {0, 0, 0, 0};

const char* nomesEfeitos[] = { "DMX SYSTEM", "MANUAL", "FADE", "STROBO", "SEQUENC", "FIXO" };

unsigned long tempoUltimaAtividade = 0;
bool telaAcesa = true;
#define TEMPO_SLEEP_TELA 60000
unsigned long ultimoDebounce = 0;

unsigned long ultimaAtualizacaoEfeito = 0;
int fadeValue = 0;
bool fadeDirection = true;
bool estadoStrobo = false;
int passoAlternado = 0;

NimBLEServer* pServer = NULL;
NimBLECharacteristic* pTxCharacteristic = NULL;
bool dispositivoConectado = false;
bool autenticado = false;
uint32_t desafioHandshake = 0;
String comandoPendente = "";
bool novoComandoBle = false;

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define TX_UUID                "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define RX_UUID                "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

Preferences preferences;

class ServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
        dispositivoConectado = true;
        autenticado = false;
        randomSeed(micros());
        desafioHandshake = random(1000, 9999);
        pServer->updateConnParams(connInfo.getConnHandle(), 16, 32, 0, 400);
    }
    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
        dispositivoConectado = false;
        autenticado = false;
        NimBLEDevice::startAdvertising();
    }
};

class CharacteristicCallbacks: public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *pCharacteristic, NimBLEConnInfo& connInfo) override {
      String rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) { comandoPendente = rxValue; novoComandoBle = true; }
    }
};

void acordaTela() {
  tempoUltimaAtividade = millis();
  if (!telaAcesa) { display.ssd1306_command(SSD1306_DISPLAYON); telaAcesa = true; }
}

void exibirTelaSalvando() {
  display.clearDisplay();
  display.setTextSize(2);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(20, 25);
  display.print("SALVANDO...");
  display.display();
}

void salvarConfiguracao() {
  preferences.begin("mileto_cfg", false);
  preferences.putInt("dmx_mode", sistemaEmModoDMX ? 1 : 0);
  preferences.putInt("modo", modoAtual);
  preferences.putInt("dmx", enderecoDMX);
  preferences.putInt("vel", velocidad);
  preferences.putInt("dim", brilhoGeral);
  for (int i = 0; i < 4; i++) {
    char kC[6], kV[7]; sprintf(kC, "ch%d", i + 1); sprintf(kV, "vch%d", i + 1);
    preferences.putInt(kC, brilhoCanais[i]);
    preferences.putInt(kV, velocidadesCanais[i]);
  }
  preferences.end();
}

void carregarConfiguracao() {
  preferences.begin("mileto_cfg", true);
  sistemaEmModoDMX = (preferences.getInt("dmx_mode", 0) == 1);
  modoAtual = preferences.getInt("modo", 1);
  enderecoDMX = preferences.getInt("dmx", 1);
  velocidad = preferences.getInt("vel", 50);
  brilhoGeral = preferences.getInt("dim", 255);
  for (int i = 0; i < 4; i++) {
    char kC[6], kV[7]; sprintf(kC, "ch%d", i + 1); sprintf(kV, "vch%d", i + 1);
    brilhoCanais[i] = preferences.getInt(kC, 255);
    velocidadesCanais[i] = preferences.getInt(kV, 100);
  }
  preferences.end();
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
  if (dispositivoConectado && autenticado && millis() - last >= 60) {
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

void atualizarDisplay() {
  if (!telaAcesa) return;
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("--- MILETO ---");

  display.setCursor(0, 16);
  if (faseAtual == FASE_MODO) display.print("> "); else display.print("  ");

  if (sistemaEmModoDMX && faseAtual != FASE_MODO) {
      display.print("MODO: DMX SYSTEM");
  } else {
      display.print("MODO: ");
      display.print(nomesEfeitos[sistemaEmModoDMX ? 0 : modoAtual]);
  }

  display.drawFastHLine(0, 28, 128, SSD1306_WHITE);

  if (sistemaEmModoDMX) {
    display.setCursor(0, 36);
    if (faseAtual == FASE_CAMPO) display.print("> "); else display.print("  ");
    display.print("Config. Canal");
    display.setCursor(0, 50);
    if (faseAtual == FASE_VALOR) display.print("[ "); else display.print("  ");
    display.print("CANAL DMX: "); display.print(enderecoDMX);
    if (faseAtual == FASE_VALOR) display.print(" ]");
  } else {
     if (modoAtual == 1) { // MANUAL
        display.setCursor(0, 32);
        if (faseAtual == FASE_CAMPO && linhaSelecionada == 1) display.print("> "); else display.print("  ");
        display.print("CH:"); display.print(canalSelecionado + 1);
        display.setCursor(0, 42);
        if (faseAtual == FASE_CAMPO && linhaSelecionada == 2) display.print("> "); else display.print("  ");
        display.print("B:"); display.print(map(brilhoCanais[canalSelecionado], 0, 255, 0, 100)); display.print("%");
        display.setCursor(64, 42);
        if (faseAtual == FASE_CAMPO && linhaSelecionada == 3) display.print("> "); else display.print("  ");
        display.print("V:"); display.print(velocidadesCanais[canalSelecionado]); display.print("%");
     } else {
        display.setCursor(0, 34);
        if (faseAtual == FASE_CAMPO && linhaSelecionada == 1) display.print("> "); else display.print("  ");
        display.print("Vel: "); display.print(velocidad); display.print("%");
        display.setCursor(0, 48);
        if (faseAtual == FASE_CAMPO && linhaSelecionada == 2) display.print("> "); else display.print("  ");
        display.print("Dim: "); display.print(map(brilhoGeral, 0, 255, 0, 100)); display.print("%");
     }
  }
  display.display();
}

int lastClkState;
void lidarComEncoder() {
  int currentClkState = digitalRead(ENC_CLK);
  if (currentClkState != lastClkState && currentClkState == LOW) {
    acordaTela();
    bool subindo = digitalRead(ENC_DT) != currentClkState;
    if (faseAtual == FASE_MODO) {
      static int selection = sistemaEmModoDMX ? 0 : modoAtual;
      if (subindo) selection = (selection + 1) % 6;
      else selection = (selection <= 0) ? 5 : selection - 1;

      if (selection == 0) { sistemaEmModoDMX = true; }
      else { sistemaEmModoDMX = false; modoAtual = selection; }
    }
    else if (!sistemaEmModoDMX) {
      if (faseAtual == FASE_CAMPO) {
        int mL = (modoAtual == 1) ? 3 : 2;
        if (subindo) { linhaSelecionada++; if (linhaSelecionada > mL) linhaSelecionada = 1; }
        else { linhaSelecionada--; if (linhaSelecionada < 1) linhaSelecionada = mL; }
      }
      else if (faseAtual == FASE_VALOR) {
        if (modoAtual == 1) {
            if (linhaSelecionada == 1) { if (subindo) canalSelecionado = (canalSelecionado + 1) % 4; else canalSelecionado = (canalSelecionado <= 0) ? 3 : canalSelecionado - 1; }
            else if (linhaSelecionada == 2) { if (subindo) brilhoCanais[canalSelecionado] = min(brilhoCanais[canalSelecionado] + 15, 255); else brilhoCanais[canalSelecionado] = max(brilhoCanais[canalSelecionado] - 15, 0); }
            else if (linhaSelecionada == 3) { if (subindo) velocidadesCanais[canalSelecionado] = min(velocidadesCanais[canalSelecionado] + 5, 100); else velocidadesCanais[canalSelecionado] = max(velocidadesCanais[canalSelecionado] - 5, 0); }
        } else {
            if (linhaSelecionada == 1) { if (subindo) velocidad = min(velocidad + 5, 100); else velocidad = max(velocidad - 5, 0); }
            else if (linhaSelecionada == 2) { if (subindo) brilhoGeral = min(brilhoGeral + 15, 255); else brilhoGeral = max(brilhoGeral - 15, 0); }
        }
      }
    } else {
      if (faseAtual == FASE_VALOR) {
        if (subindo) { enderecoDMX++; if (enderecoDMX > 512) enderecoDMX = 1; }
        else { enderecoDMX--; if (enderecoDMX < 1) enderecoDMX = 512; }
        if (dispositivoConectado && autenticado) {
           String syncMsg = "DMX:" + String(enderecoDMX) + "\n";
           pTxCharacteristic->setValue(syncMsg.c_str()); pTxCharacteristic->notify();
        }
      }
    }
    atualizarDisplay();
  }
  lastClkState = currentClkState;

  int currentSwState = digitalRead(ENC_SW);
  static int lastSwState = HIGH;
  if (currentSwState != lastSwState && currentSwState == LOW) {
    if (millis() - ultimoDebounce >= 250) {
      ultimoDebounce = millis();
      acordaTela();
      if (faseAtual == FASE_MODO) { faseAtual = FASE_CAMPO; linhaSelecionada = 1; }
      else if (faseAtual == FASE_CAMPO) { faseAtual = FASE_VALOR; }
      else if (faseAtual == FASE_VALOR) {
        exibirTelaSalvando(); salvarConfiguracao(); delay(500);
        if (dispositivoConectado && autenticado) {
          String msg = "MODO:" + String(sistemaEmModoDMX ? 0 : modoAtual) + "|DMX:" + String(enderecoDMX) + "\n";
          pTxCharacteristic->setValue(msg.c_str()); pTxCharacteristic->notify();
        }
        faseAtual = FASE_MODO; linhaSelecionada = 0;
      }
      atualizarDisplay();
    }
  }
  lastSwState = currentSwState;
}

void setRS485Direction(bool transmitir) {
  if (transmitir) {
    digitalWrite(RS485_DIR_PIN, HIGH);
    delayMicroseconds(5);
  } else {
    uart_wait_tx_done(DMX_UART_NUM, portMAX_DELAY);
    digitalWrite(RS485_DIR_PIN, LOW);
  }
}

void executarVarreduraRDM() {
  if (!dispositivoConectado || !autenticado) return;

  pTxCharacteristic->setValue("RDM_START\n");
  pTxCharacteristic->notify();
  delay(100);

  // Simulação de resposta RDM
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
  comandoPendente.replace("\n", ""); comandoPendente.replace("\r", ""); comandoPendente.trim();
  int div = comandoPendente.indexOf(':'); if (div == -1) return;
  String cmd = comandoPendente.substring(0, div); String val = comandoPendente.substring(div + 1);
  int iv = val.toInt();

  if (cmd == "AUTH_RESPONSE") {
    if (iv == (desafioHandshake * 2) + 7) {
      autenticado = true;
      pTxCharacteristic->setValue("MILETO_AUTH:VALID\nCONNECTED_OK\n"); pTxCharacteristic->notify();
    } else {
      autenticado = false;
      pTxCharacteristic->setValue("MILETO_AUTH:INVALID\n"); pTxCharacteristic->notify();
    }
    return;
  }
  if (!autenticado) return;

  if (cmd == "SET_CH1") brilhoCanais[0] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_CH2") brilhoCanais[1] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_CH3") brilhoCanais[2] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_CH4") brilhoCanais[3] = map(iv, 0, 100, 0, 255);
  else if (cmd == "SET_VCH1") velocidadesCanais[0] = iv;
  else if (cmd == "SET_VCH2") velocidadesCanais[1] = iv;
  else if (cmd == "SET_VCH3") velocidadesCanais[2] = iv;
  else if (cmd == "SET_VCH4") velocidadesCanais[3] = iv;
  else if (cmd == "SET_MODO") {
    if (iv == 0) { sistemaEmModoDMX = true; }
    else { sistemaEmModoDMX = false; modoAtual = iv; }
  }
  else if (cmd == "SET_VEL") { velocidad = min(iv, 100); }
  else if (cmd == "SET_DIM") { brilhoGeral = map(iv, 0, 100, 0, 255); }
  else if (cmd == "SET_DMX") { enderecoDMX = iv; }
  else if (cmd == "VARREDURA_RDM") { executarVarreduraRDM(); }
  else if (cmd == "CHAVE_MODO") { sistemaEmModoDMX = (val == "DMX"); if(!sistemaEmModoDMX && modoAtual == 0) modoAtual = 1; }
  else if (cmd == "GRAVAR") { exibirTelaSalvando(); salvarConfiguracao(); pTxCharacteristic->setValue("GRAVAR:OK\n"); pTxCharacteristic->notify(); delay(1000); }
  atualizarDisplay();
}

void executarEfeitos(int modo) {
  unsigned long tempo = millis();
  int d = map(velocidad, 0, 100, 800, 25);
  if (modo == 1) { // MANUAL
      static unsigned long ts[4] = {0,0,0,0}; static bool sts[4] = {0,0,0,0};
      for(int i=0; i<4; i++){
        if(sistemaEmModoDMX || velocidadesCanais[i] >= 100) sts[i] = 1;
        else {
          int dv = map(velocidadesCanais[i], 0, 99, 800, 40);
          if(tempo - ts[i] >= (unsigned long)dv){ ts[i] = tempo; sts[i] = !sts[i]; }
        }
        writeChannel(i, sts[i] ? (brilhoCanais[i]*brilhoGeral)/255 : 0);
      }
  } else if (brilhoGeral == 0) { for(int i=0; i<4; i++) writeChannel(i, 0); }
  else {
    switch (modo) {
      case 2: // FADE
        if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d / 12) {
          ultimaAtualizacaoEfeito = tempo; if (fadeDirection) fadeValue++; else fadeValue--;
          if (fadeValue >= 255) { fadeValue = 255; fadeDirection = false; } else if (fadeValue <= 0) { fadeValue = 0; fadeDirection = true; }
          writeChannel(0, (fadeValue * brilhoGeral) / 255); writeChannel(1, ((255 - fadeValue) * brilhoGeral) / 255);
          writeChannel(2, ((255 - fadeValue) * brilhoGeral) / 255); writeChannel(3, (fadeValue * brilhoGeral) / 255);
        } break;
      case 3: // STROBO
        if (velocidad >= 100) for(int i=0; i<4; i++) writeChannel(i, brilhoGeral);
        else if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d) {
          ultimaAtualizacaoEfeito = tempo; estadoStrobo = !estadoStrobo;
          int v = estadoStrobo ? brilhoGeral : 0; for(int i=0; i<4; i++) writeChannel(i, v);
        } break;
      case 4: // SEQUENC
        if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d) {
          ultimaAtualizacaoEfeito = tempo; passoAlternado = (passoAlternado + 1) % 4;
          for(int i=0; i<4; i++) writeChannel(i, (passoAlternado == i) ? brilhoGeral : 0);
        } break;
      case 5: for(int i=0; i<4; i++) writeChannel(i, brilhoGeral); break;
    }
  }
}

void processarDMX() {
  uart_event_t evt;
  while (xQueueReceive(dmx_queue, (void*)&evt, 0)) {
    if (evt.type == UART_BREAK) { uart_flush_input(DMX_UART_NUM); dmx_idx = 0; dmx_em_frame = true; }
    else if (evt.type == UART_DATA && dmx_em_frame) {
      size_t l = 0; uart_get_buffered_data_len(DMX_UART_NUM, &l);
      if (l > 0) {
        uint8_t t[64]; int r = uart_read_bytes(DMX_UART_NUM, t, (l > 64) ? 64 : l, 0);
        for (int i = 0; i < r; i++) {
          if (dmx_em_frame) {
            if (dmx_idx < 520) raw_dmx_buf[dmx_idx] = t[i]; dmx_idx++;
            if (dmx_idx >= (enderecoDMX + 7)) {
              if (raw_dmx_buf[0] == 0x00) {
                int idx = enderecoDMX;
                for(int c=0; c<4; c++) brilhoCanais[c] = raw_dmx_buf[idx+c];
                brilhoGeral = raw_dmx_buf[idx+4]; velocidad = map(raw_dmx_buf[idx+5], 0, 255, 0, 100);
                int m = raw_dmx_buf[idx+6];
                if (m <= 50) modoDMXTemp = 1; else if (m <= 100) modoDMXTemp = 2;
                else if (m <= 150) modoDMXTemp = 3; else if (m <= 200) modoDMXTemp = 4; else modoDMXTemp = 5;
              }
              dmx_em_frame = false;
            }
          }
        }
      }
    }
  }
}

void desenharLogo(const unsigned char* bitmap, int largura, int altura) {
  display.clearDisplay();
  display.drawBitmap(0, 0, bitmap, largura, altura, WHITE);
  display.display();
}

void setup() {
  Serial.begin(115200);
  Serial.println("MILETO STARTING...");
  tempoUltimaAtividade = millis();
  pinMode(ENC_CLK, INPUT_PULLUP);
  pinMode(ENC_DT, INPUT_PULLUP);
  pinMode(ENC_SW, INPUT_PULLUP);
  pinMode(RS485_DIR_PIN, OUTPUT);
  digitalWrite(RS485_DIR_PIN, LOW); // Recepção padrão
  lastClkState = digitalRead(ENC_CLK);
  ledcAttach(MOSFET_CH1, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH2, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH3, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH4, PWM_FREQ, PWM_RES);
  Wire.begin(8, 9);
  if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) { Serial.println("OLED ERR"); }
  display.setTextColor(SSD1306_WHITE);
  desenharLogo(MILETO_LOGO_1, LARGURA_TELA, ALTURA_TELA);
  delay(3000);
  carregarConfiguracao();
  atualizarDisplay();
  NimBLEDevice::init("MILETO");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(TX_UUID, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic *pRxCharacteristic = pService->createCharacteristic(RX_UUID, NIMBLE_PROPERTY::WRITE);
  pRxCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pService->start();
  NimBLEDevice::setOwnAddrType(BLE_OWN_ADDR_RANDOM);
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  BLEAdvertisementData mainAdv;
  mainAdv.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  mainAdv.setCompleteServices(BLEUUID(SERVICE_UUID));
  mainAdv.setName("MILETO");
  pAdvertising->setAdvertisementData(mainAdv);
  BLEAdvertisementData scanResponseData;
  scanResponseData.setName("MILETO");
  pAdvertising->setScanResponseData(scanResponseData);
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->enableScanResponse(true);
  pAdvertising->setMinInterval(32);
  pAdvertising->setMaxInterval(64);
  pAdvertising->start();
  uart_config_t uart_cfg = { .baud_rate = 250000, .data_bits = UART_DATA_8_BITS, .parity = UART_PARITY_DISABLE, .stop_bits = UART_STOP_BITS_2, .flow_ctrl = UART_HW_FLOWCTRL_DISABLE, .source_clk = UART_SCLK_DEFAULT };
  uart_param_config(DMX_UART_NUM, &uart_cfg);
  uart_set_pin(DMX_UART_NUM, UART_PIN_NO_CHANGE, DMX_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  uart_driver_install(DMX_UART_NUM, 1024, 0, 20, &dmx_queue, 0);
  Serial.println("MILETO READY!");
}

void loop() {
  if (novoComandoBle) { processarBluetooth(); novoComandoBle = false; comandoPendente = ""; }
  static bool ultimoEstadoConexao = false;
  static unsigned long lastAuthReq = 0;
  if (dispositivoConectado != ultimoEstadoConexao) {
    ultimoEstadoConexao = dispositivoConectado;
    if (dispositivoConectado) { lastAuthReq = millis(); acordaTela(); }
    atualizarDisplay();
  }
  if (dispositivoConectado && !autenticado && millis() - lastAuthReq >= 2000) {
    lastAuthReq = millis();
    String msg = "AUTH_CHALLENGE:"; msg += desafioHandshake; msg += "\n";
    pTxCharacteristic->setValue(msg.c_str()); pTxCharacteristic->notify();
  }
  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    display.clearDisplay(); display.display();
    display.ssd1306_command(SSD1306_DISPLAYOFF);
    telaAcesa = false;
  }
  lidarComEncoder();
  if (sistemaEmModoDMX) { processarDMX(); executarEfeitos(modoDMXTemp); }
  else { executarEfeitos(modoAtual); }
  enviarNiveisBT();
}