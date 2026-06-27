#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>

/*
 * MILETO - CONTROLE DE PISTA LED 4 CANAIS (ESP32-C3 SUPER MINI)
 *
 * ATENÇÃO HARDWARE: O ESP32-C3 NÃO suporta Bluetooth Classic (BluetoothSerial).
 * Para usar com o App via Bluetooth no C3 Super Mini, é necessário migrar
 * para a biblioteca NimBLE ou BLE standard.
 *
 * PINOUT ADAPTADO PARA C3 SUPER MINI (Evitando conflitos):
 */

#include "BluetoothSerial.h"
#include "SSD1306Ascii.h"
#include "SSD1306AsciiWire.h"
#include "driver/uart.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "MILETO_LOGO_1.h"

#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error O Bluetooth nao esta ativado!
#endif

SSD1306AsciiWire oled;
Preferences preferences;
BluetoothSerial SerialBT;

// --- CONFIGURAÇÃO UART DMX512 (ESP32-C3: UART 1) ---
#define DMX_UART_NUM UART_NUM_1
#define DMX_RX_PIN 20
#define DMX_TX_PIN UART_PIN_NO_CHANGE

static QueueHandle_t dmx_queue;
uint8_t raw_dmx_buf[515];
int dmx_idx = 0;
bool dmx_em_frame = false;

// --- MAPEAMENTO DE PINOS (ESP32-C3 SUPER MINI) ---
// MOSFETs (PWM)
#define MOSFET_CH1 0
#define MOSFET_CH2 1
#define MOSFET_CH3 2
#define MOSFET_CH4 3

// Painel de Controle (Botões)
#define BTN_MUDAR_CAMPO 4   // Botão 1: VOLTAR
#define BTN_FRENTE 5        // Botão 2: +
#define BTN_VOLTA 6         // Botão 3: -
#define BTN_GRAVAR 7        // Botão 4: OK
#define CHAVE_DMX_MANUAL 10 // Alternador DMX/Manual

// LED de Status
#define LED_STATUS_DMX 21

#define PWM_FREQ 4000
#define PWM_RES 8

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
unsigned long ultimoPiscaStatus = 0;
bool estadoLedStatus = false;
bool dispositivoConectado = false;

void atualizarDisplay();
void acordaTela();
void executarEfeitos();
void writeChannel(int ch, int val);
void enviarNiveisBT();
void processarMesaDMX();
void imprimeNumero(int num);
void salvarConfiguracao();
void receberDadosBluetooth();
void processarComandoApp(String pacote);
void desenharLogo(const uint8_t* bitmap);

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  Serial.begin(115200);

  pinMode(LED_STATUS_DMX, OUTPUT);
  pinMode(BTN_MUDAR_CAMPO, INPUT_PULLUP);
  pinMode(BTN_FRENTE, INPUT_PULLUP);
  pinMode(BTN_VOLTA, INPUT_PULLUP);
  pinMode(BTN_GRAVAR, INPUT_PULLUP);
  pinMode(CHAVE_DMX_MANUAL, INPUT_PULLUP);

  ledcAttach(MOSFET_CH1, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH2, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH3, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH4, PWM_FREQ, PWM_RES);

  // I2C para ESP32-C3 Super Mini (SDA=8, SCL=9)
  Wire.begin(8, 9);
  oled.begin(&Adafruit128x64, 0x3C);
  oled.setFont(Adafruit5x7);

  desenharLogo(MILETO_LOGO_1);
  delay(2000);

  // Carrega configurações persistentes
  preferences.begin("mileto_cfg", false);
  enderecoDMX = preferences.getInt("dmx", 1);
  modoAtual = preferences.getInt("modo", 0);
  velocidad = preferences.getInt("vel", 100);
  brilhoGeral = preferences.getInt("dim", 255);
  for (int i = 0; i < 4; i++) {
    char kCh[6], kV[7];
    sprintf(kCh, "ch%d", i + 1);
    sprintf(kV, "vch%d", i + 1);
    brilhoCanais[i] = preferences.getInt(kCh, 255);
    velocidadesCanais[i] = preferences.getInt(kV, 100);
  }
  preferences.end();

  // Configuração UART DMX
  uart_config_t uart_cfg = {
    .baud_rate = 250000,
    .data_bits = UART_DATA_8_BITS,
    .parity = UART_PARITY_DISABLE,
    .stop_bits = UART_STOP_BITS_2,
    .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
    .source_clk = UART_SCLK_DEFAULT
  };
  uart_param_config(DMX_UART_NUM, &uart_cfg);
  uart_set_pin(DMX_UART_NUM, DMX_TX_PIN, DMX_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  uart_driver_install(DMX_UART_NUM, 1024, 0, 20, &dmx_queue, 0);

  SerialBT.begin("MILETO_C3");
  tempoUltimaAtividade = millis();
  atualizarDisplay();
}

void loop() {
  // LED de Status
  if (sistemaEmModoDMX) {
    sinalDMXAtivo = (millis() - ultimoPacoteDMX < 1000);
    if (sinalDMXAtivo) {
      if (millis() - ultimoPiscaStatus >= 70) {
        ultimoPiscaStatus = millis(); estadoLedStatus = !estadoLedStatus;
        digitalWrite(LED_STATUS_DMX, estadoLedStatus);
      }
    } else digitalWrite(LED_STATUS_DMX, LOW);
  } else if (!dispositivoConectado) {
    if (millis() - ultimoPiscaStatus >= 200) {
      ultimoPiscaStatus = millis(); estadoLedStatus = !estadoLedStatus;
      digitalWrite(LED_STATUS_DMX, estadoLedStatus);
    }
  } else digitalWrite(LED_STATUS_DMX, HIGH);

  // Troca de Modo
  if (digitalRead(CHAVE_DMX_MANUAL) == LOW && (millis() - ultimoDebounce >= 250)) {
    ultimoDebounce = millis(); acordaTela();
    sistemaEmModoDMX = !sistemaEmModoDMX;
    if (!sistemaEmModoDMX) {
      preferences.begin("mileto_cfg", true);
      modoAtual = preferences.getInt("modo", 0);
      velocidad = preferences.getInt("vel", 100);
      brilhoGeral = preferences.getInt("dim", 255);
      for(int i=0; i<4; i++){
        char kCh[6], kV[7]; sprintf(kCh,"ch%d",i+1); sprintf(kV,"vch%d",i+1);
        brilhoCanais[i] = preferences.getInt(kCh, 255);
        velocidadesCanais[i] = preferences.getInt(kV, 100);
      }
      preferences.end();
    }
    if (dispositivoConectado) { SerialBT.print("CHAVE_MODO:"); SerialBT.println(sistemaEmModoDMX ? "DMX" : "RF"); }
    atualizarDisplay();
  }

  // Navegação Menu
  if (!sistemaEmModoDMX) {
    if (digitalRead(BTN_MUDAR_CAMPO) == LOW && (millis() - ultimoDebounce >= 250)) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_CAMPO) { faseAtual = FASE_MODO; linhaSelecionada = 0; }
      else if (faseAtual == FASE_VALOR) faseAtual = FASE_CAMPO;
      atualizarDisplay();
    }
    if (digitalRead(BTN_FRENTE) == LOW && (millis() - ultimoDebounce >= 150)) {
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
    if (digitalRead(BTN_VOLTA) == LOW && (millis() - ultimoDebounce >= 150)) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_MODO) modoAtual = (modoAtual > 0) ? modoAtual - 1 : 4;
      else if (faseAtual == FASE_CAMPO) linhaSelecionada = (linhaSelecionada == 1) ? 2 : 1;
      else if (faseAtual == FASE_VALOR) {
        if (linhaSelecionada == 1) {
          if (modoAtual == 0) canalSelecionado = (canalSelecionado > 0) ? canalSelecionado - 1 : 3;
          else velocidad = max(velocidad - 5, 0);
        } else if (linhaSelecionada == 2) {
          if (modoAtual == 0) brilhoCanais[canalSelecionado] = max(brilhoCanais[canalSelecionado] - 15, 0);
          else brilhoGeral = max(brilhoGeral - 15, 0);
        }
      }
      atualizarDisplay();
    }
    if (digitalRead(BTN_GRAVAR) == LOW && (millis() - ultimoDebounce >= 250)) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_MODO) { faseAtual = FASE_CAMPO; linhaSelecionada = 1; }
      else if (faseAtual == FASE_CAMPO) faseAtual = FASE_VALOR;
      else if (faseAtual == FASE_VALOR) {
        oled.clear(); oled.write("\n\n   GRAVANDO...\n"); salvarConfiguracao(); delay(700);
        faseAtual = FASE_MODO; linhaSelecionada = 0;
      }
      atualizarDisplay();
    }
  } else {
    // Endereço DMX
    if (digitalRead(BTN_FRENTE) == LOW && (millis() - ultimoDebounce >= 150)) {
      ultimoDebounce = millis(); acordaTela(); enderecoDMX = (enderecoDMX % 512) + 1; atualizarDisplay();
    }
    if (digitalRead(BTN_VOLTA) == LOW && (millis() - ultimoDebounce >= 150)) {
      ultimoDebounce = millis(); acordaTela(); enderecoDMX = (enderecoDMX <= 1) ? 512 : enderecoDMX - 1; atualizarDisplay();
    }
    if (digitalRead(BTN_GRAVAR) == LOW && (millis() - ultimoDebounce >= 250)) {
      ultimoDebounce = millis(); acordaTela(); oled.clear(); oled.write("\n\n   DMX SALVO!"); salvarConfiguracao(); delay(700); atualizarDisplay();
    }
  }

  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    oled.clear(); oled.ssd1306WriteCmd(SSD1306_DISPLAYOFF); telaAcesa = false;
  }

  receberDadosBluetooth();
  if (sistemaEmModoDMX) processarMesaDMX();
  executarEfeitos();
}

void desenharLogo(const uint8_t* bitmap) {
  oled.clear();
  for (uint8_t p = 0; p < 8; p++) {
    oled.setCursor(0, p);
    for (uint8_t c = 0; c < 128; c++) oled.ssd1306WriteRam(pgm_read_byte(&bitmap[p * 128 + c]));
  }
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
    last = millis(); SerialBT.print("CH_LEVELS:");
    for(int i=0; i<4; i++){ SerialBT.print(map(niveisAtuais[i],0,255,0,100)); if(i<3) SerialBT.print(","); }
    SerialBT.println();
  }
}

void executarEfeitos() {
  unsigned long tempo = millis();
  int d = map(velocidad, 0, 100, 800, 25);

  if (modoAtual == 0) { // MANUAL
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
    enviarNiveisBT(); return;
  }

  if (brilhoGeral == 0) { for(int i=0; i<4; i++) writeChannel(i, 0); enviarNiveisBT(); return; }

  switch (modoAtual) {
    case 1: // FADE FLUIDO
      if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d / 12) {
        ultimaAtualizacaoEfeito = tempo; if (fadeDirection) fadeValue++; else fadeValue--;
        if (fadeValue >= 255) { fadeValue = 255; fadeDirection = false; } else if (fadeValue <= 0) { fadeValue = 0; fadeDirection = true; }
        writeChannel(0, (fadeValue * brilhoGeral) / 255); writeChannel(1, ((255 - fadeValue) * brilhoGeral) / 255);
        writeChannel(2, ((255 - fadeValue) * brilhoGeral) / 255); writeChannel(3, (fadeValue * brilhoGeral) / 255);
      }
      break;
    case 2: // STROBO
      if (velocidad >= 100) for(int i=0; i<4; i++) writeChannel(i, brilhoGeral);
      else if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d) {
        ultimaAtualizacaoEfeito = tempo; estadoStrobo = !estadoStrobo;
        int v = estadoStrobo ? brilhoGeral : 0; for(int i=0; i<4; i++) writeChannel(i, v);
      }
      break;
    case 3: // SEQUENCIAL
      if (tempo - ultimaAtualizacaoEfeito >= (unsigned long)d) {
        ultimaAtualizacaoEfeito = tempo; passoAlternado = (passoAlternado + 1) % 4;
        for(int i=0; i<4; i++) writeChannel(i, (passoAlternado == i) ? brilhoGeral : 0);
      }
      break;
    case 4: // FIXO
      for(int i=0; i<4; i++) writeChannel(i, brilhoGeral);
      break;
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
          if (dmx_idx < 515) raw_dmx_buf[dmx_idx] = t[i]; dmx_idx++;
          if (dmx_idx >= (enderecoDMX + 7)) {
            if (raw_dmx_buf[0] == 0x00) {
              ultimoPacoteDMX = millis(); int idx = enderecoDMX;
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

void receberDadosBluetooth() {
  if (SerialBT.available()) {
    acordaTela(); if (!dispositivoConectado) { dispositivoConectado = true; SerialBT.println("CONNECTED"); }
    String p = SerialBT.readStringUntil('\n'); p.trim();
    if (p.length() > 0) { processarComandoApp(p); atualizarDisplay(); }
  }
  if (dispositivoConectado && !SerialBT.hasClient()) { dispositivoConectado = false; atualizarDisplay(); }
}

void processarComandoApp(String p) {
  int div = p.indexOf(':'); if (div == -1) return;
  String cmd = p.substring(0, div); String val = p.substring(div + 1);
  bool ok = true;
  if (cmd == "CHAVE_MODO") sistemaEmModoDMX = (val == "DMX");
  else if (cmd == "SET_MODO") modoAtual = val.toInt();
  else if (cmd == "SET_VEL") velocidad = val.toInt();
  else if (cmd == "SET_DIM") brilhoGeral = map(val.toInt(), 0, 100, 0, 255);
  else if (cmd == "SET_DMX") enderecoDMX = val.toInt();
  else if (cmd.startsWith("SET_CH")) {
    int c = cmd.substring(6).toInt()-1;
    if(c>=0 && c<4) brilhoCanais[c] = map(val.toInt(), 0, 100, 0, 255);
  } else if (cmd.startsWith("SET_VCH")) {
    int c = cmd.substring(7).toInt()-1;
    if(c>=0 && c<4) velocidadesCanais[c] = val.toInt();
  } else if (cmd == "GRAVAR") { salvarConfiguracao(); SerialBT.println("GRAVAR:OK"); }
  else ok = false;
  if (dispositivoConectado && ok) { SerialBT.print("ACK_"); SerialBT.print(cmd); Serial.println(":OK"); }
}

void acordaTela() { tempoUltimaAtividade = millis(); if (!telaAcesa) { oled.ssd1306WriteCmd(SSD1306_DISPLAYON); telaAcesa = true; } }

void salvarConfiguracao() {
  preferences.begin("mileto_cfg", false);
  preferences.putInt("dmx", enderecoDMX); preferences.putInt("modo", modoAtual);
  preferences.putInt("vel", velocidad); preferences.putInt("dim", brilhoGeral);
  for (int i = 0; i < 4; i++) {
    char kCh[6], kV[7]; sprintf(kCh, "ch%d", i + 1); sprintf(kV, "vch%d", i + 1);
    preferences.putInt(kCh, brilhoCanais[i]); preferences.putInt(kV, velocidadesCanais[i]);
  }
  preferences.end();
}

void imprimeNumero(int n) { if(n==0){ oled.write('0'); return; } char b[6]; sprintf(b,"%d",n); oled.write(b); }

void atualizarDisplay() {
  if (!telaAcesa) return;
  oled.clear();
  if (sistemaEmModoDMX) {
    oled.write("--- MESA DMX: 7 CHs ---\n\nSTATUS: "); oled.write(sinalDMXAtivo ? "OK\n" : "OFF\n");
    oled.write("MODO: "); oled.write(nomesEfeitos[modoAtual]); oled.write("\n\n");
    oled.set2X(); oled.write("CH: "); imprimeNumero(enderecoDMX); oled.set1X();
  } else {
    oled.write(dispositivoConectado ? "* APP CONECTADO *\n" : "--- PAINEL MANUAL ---\n");
    oled.write((faseAtual == FASE_MODO) ? "> MODO: " : "  MODO: "); oled.write(nomesEfeitos[modoAtual]); oled.write("\n");
    if (modoAtual == 0) {
      oled.write((faseAtual == FASE_CAMPO && linhaSelecionada == 1) ? "> CANAL: CH" : "  CANAL: CH"); imprimeNumero(canalSelecionado + 1); oled.write("\n");
      oled.write((faseAtual == FASE_CAMPO && linhaSelecionada == 2) ? "> BRILHO: " : "  BRILHO: "); imprimeNumero(map(brilhoCanais[canalSelecionado], 0, 255, 0, 100)); oled.write("%\n");
    } else {
      oled.write((faseAtual == FASE_CAMPO && linhaSelecionada == 1) ? "> VELOC: " : "  VELOC: "); imprimeNumero(velocidad); oled.write("%\n");
      oled.write((faseAtual == FASE_CAMPO && linhaSelecionada == 2) ? "> BRILHO: " : "  BRILHO: "); imprimeNumero(map(brilhoGeral, 0, 255, 0, 100)); oled.write("%\n");
    }
  }
}
