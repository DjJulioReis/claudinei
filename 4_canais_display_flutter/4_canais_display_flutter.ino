#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>

/*
 * MILETO - FIRMWARE ESP32-C3 SUPER MINI (V5.4)
 *
 * Unifica correções de hardware (OLED Adafruit, pinos C3)
 * com análise em tempo real (Telemetry) e controle independente.
 */

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "BluetoothSerial.h"
#include "driver/uart.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "MILETO_LOGO_1.h"

#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error O Bluetooth nao esta ativado!
#endif

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 oled(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

Preferences preferences;
BluetoothSerial SerialBT;

// --- CONFIGURAÇÃO UART DMX512 ---
#define DMX_UART_NUM UART_NUM_1
#define DMX_RX_PIN 20
#define DMX_TX_PIN UART_PIN_NO_CHANGE

static QueueHandle_t dmx_queue;
uint8_t raw_dmx_buf[515];
int dmx_idx = 0;
bool dmx_em_frame = false;

// --- MAPEAMENTO DE PINOS (ESP32-C3 SUPER MINI) ---
#define MOSFET_CH1 0
#define MOSFET_CH2 1
#define MOSFET_CH3 5
#define MOSFET_CH4 4

#define BTN_MUDAR_CAMPO 6
#define BTN_FRENTE      7
#define BTN_VOLTA      10
#define BTN_GRAVAR      21
#define CHAVE_DMX_MANUAL 3

#define LED_STATUS_DMX 8 // Pino disponível para LED no C3

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
bool dispositivoConectado = false;

void atualizarDisplay();
void acordaTela();
void executarEfeitos();
void writeChannel(int ch, int val);
void enviarNiveisBT();
void processarMesaDMX();
void salvarConfiguracao();
void receberDadosBluetooth();
void processarComandoApp(String pacote);
void desenharLogo(const uint8_t* bitmap);

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  Serial.begin(115200);

  Wire.begin(8, 9);
  if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED nao encontrado");
    while (1);
  }
  oled.setTextColor(SSD1306_WHITE);

  pinMode(BTN_MUDAR_CAMPO, INPUT_PULLUP);
  pinMode(BTN_FRENTE, INPUT_PULLUP);
  pinMode(BTN_VOLTA, INPUT_PULLUP);
  pinMode(BTN_GRAVAR, INPUT_PULLUP);
  pinMode(CHAVE_DMX_MANUAL, INPUT_PULLUP);
  pinMode(LED_STATUS_DMX, OUTPUT);

  ledcAttach(MOSFET_CH1, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH2, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH3, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH4, PWM_FREQ, PWM_RES);

  desenharLogo(MILETO_LOGO_1);
  delay(3000);

  preferences.begin("mileto_cfg", false);
  enderecoDMX = preferences.getInt("dmx", 1);
  modoAtual = preferences.getInt("modo", 0);
  velocidad = preferences.getInt("vel", 100);
  brilhoGeral = preferences.getInt("dim", 255);
  for (int i = 0; i < 4; i++) {
    char kC[6], kV[7]; sprintf(kC,"ch%d",i+1); sprintf(kV,"vch%d",i+1);
    brilhoCanais[i] = preferences.getInt(kC, 255);
    velocidadesCanais[i] = preferences.getInt(kV, 100);
  }
  preferences.end();

  uart_config_t uart_cfg = {
    .baud_rate = 250000,
    .data_bits = UART_DATA_8_BITS,
    .parity = UART_PARITY_DISABLE,
    .stop_bits = UART_STOP_BITS_2,
    .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
    .source_clk = UART_SCLK_DEFAULT
  };
  uart_param_config(DMX_UART_NUM, &uart_cfg);
  uart_set_pin(DMX_UART_NUM, UART_PIN_NO_CHANGE, DMX_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  uart_driver_install(DMX_UART_NUM, 1024, 0, 20, &dmx_queue, 0);

  SerialBT.begin("MILETO_C3");
  tempoUltimaAtividade = millis();
  atualizarDisplay();
}

void loop() {
  static unsigned long lastFlash = 0;
  if (sistemaEmModoDMX) {
    sinalDMXAtivo = (millis() - ultimoPacoteDMX < 1000);
    if (sinalDMXAtivo && millis() - lastFlash >= 70) {
      lastFlash = millis(); digitalWrite(LED_STATUS_DMX, !digitalRead(LED_STATUS_DMX));
    } else if (!sinalDMXAtivo) digitalWrite(LED_STATUS_DMX, LOW);
  } else if (!dispositivoConectado) {
    if (millis() - lastFlash >= 200) {
      lastFlash = millis(); digitalWrite(LED_STATUS_DMX, !digitalRead(LED_STATUS_DMX));
    }
  } else digitalWrite(LED_STATUS_DMX, HIGH);

  if (digitalRead(CHAVE_DMX_MANUAL) == LOW && millis() - ultimoDebounce >= 250) {
    ultimoDebounce = millis(); acordaTela();
    sistemaEmModoDMX = !sistemaEmModoDMX;
    if (!sistemaEmModoDMX) {
      preferences.begin("mileto_cfg", true);
      modoAtual = preferences.getInt("modo", 0);
      velocidad = preferences.getInt("vel", 100);
      brilhoGeral = preferences.getInt("dim", 255);
      for(int i=0; i<4; i++){
        char kC[6], kV[7]; sprintf(kC,"ch%d",i+1); sprintf(kV,"vch%d",i+1);
        brilhoCanais[i] = preferences.getInt(kC, 255);
        velocidadesCanais[i] = preferences.getInt(kV, 100);
      }
      preferences.end();
    }
    if (dispositivoConectado) { SerialBT.print("CHAVE_MODO:"); SerialBT.println(sistemaEmModoDMX ? "DMX" : "RF"); }
    atualizarDisplay();
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
        if (linhaSelecionada == 1) { if (modoAtual == 0) canalSelecionado = (canalSelecionado + 1) % 4; else velocidad = min(velocidad + 5, 100); }
        else if (linhaSelecionada == 2) { if (modoAtual == 0) brilhoCanais[canalSelecionado] = min(brilhoCanais[canalSelecionado] + 15, 255); else brilhoGeral = min(brilhoGeral + 15, 255); }
      }
      atualizarDisplay();
    }
    if (digitalRead(BTN_VOLTA) == LOW && millis() - ultimoDebounce >= 150) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_MODO) modoAtual = (modoAtual > 0) ? modoAtual - 1 : 4;
      else if (faseAtual == FASE_CAMPO) linhaSelecionada = (linhaSelecionada == 1) ? 2 : 1;
      else if (faseAtual == FASE_VALOR) {
        if (linhaSelecionada == 1) { if (modoAtual == 0) canalSelecionado = (canalSelecionado > 0) ? canalSelecionado - 1 : 3; else velocidad = max(velocidad - 5, 0); }
        else if (linhaSelecionada == 2) { if (modoAtual == 0) brilhoCanais[canalSelecionado] = max(brilhoCanais[canalSelecionado] - 15, 0); else brilhoGeral = max(brilhoGeral - 15, 0); }
      }
      atualizarDisplay();
    }
    if (digitalRead(BTN_GRAVAR) == LOW && millis() - ultimoDebounce >= 250) {
      ultimoDebounce = millis(); acordaTela();
      if (faseAtual == FASE_MODO) { faseAtual = FASE_CAMPO; linhaSelecionada = 1; }
      else if (faseAtual == FASE_CAMPO) faseAtual = FASE_VALOR;
      else if (faseAtual == FASE_VALOR) {
        oled.clearDisplay(); oled.setCursor(10, 15); oled.print("GRAVANDO..."); oled.display();
        salvarConfiguracao(); delay(700);
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
      ultimoDebounce = millis(); acordaTela(); oled.clearDisplay(); oled.setCursor(10, 15); oled.print("DMX SALVO!"); oled.display();
      salvarConfiguracao(); delay(700); atualizarDisplay();
    }
  }

  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    oled.clearDisplay(); oled.ssd1306_command(SSD1306_DISPLAYOFF); oled.display(); telaAcesa = false;
  }
  receberDadosBluetooth();
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
    last = millis(); SerialBT.print("CH_LEVELS:");
    for(int i=0; i<4; i++){ SerialBT.print(map(niveisAtuais[i],0,255,0,100)); if(i<3) SerialBT.print(","); }
    SerialBT.println();
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
  if (cmd == "CHAVE_MODO") sistemaEmModoDMX = (val == "DMX");
  else if (cmd == "SET_MODO") modoAtual = val.toInt();
  else if (cmd == "SET_VEL") velocidad = val.toInt();
  else if (cmd == "SET_DIM") brilhoGeral = map(val.toInt(), 0, 100, 0, 255);
  else if (cmd == "SET_DMX") enderecoDMX = val.toInt();
  else if (cmd.startsWith("SET_CH")) { int c = cmd.substring(6).toInt()-1; if(c>=0 && c<4) brilhoCanais[c] = map(val.toInt(), 0, 100, 0, 255); }
  else if (cmd.startsWith("SET_VCH")) { int c = cmd.substring(7).toInt()-1; if(c>=0 && c<4) velocidadesCanais[c] = val.toInt(); }
  else if (cmd == "GRAVAR") { salvarConfiguracao(); SerialBT.println("GRAVAR:OK"); }
  if (dispositivoConectado) { SerialBT.print("ACK_"); SerialBT.print(cmd); SerialBT.println(":OK"); }
}

void acordaTela() { tempoUltimaAtividade = millis(); if (!telaAcesa) { oled.ssd1306_command(SSD1306_DISPLAYON); telaAcesa = true; } }

void salvarConfiguracao() {
  preferences.begin("mileto_cfg", false);
  preferences.putInt("dmx", enderecoDMX); preferences.putInt("modo", modoAtual);
  preferences.putInt("vel", velocidad); preferences.putInt("dim", brilhoGeral);
  for (int i = 0; i < 4; i++) {
    char kC[6], kV[7]; sprintf(kC,"ch%d",i+1); sprintf(kV,"vch%d",i+1);
    preferences.putInt(kC, brilhoCanais[i]); preferences.putInt(kV, velocidadesCanais[i]);
  }
  preferences.end();
}

void atualizarDisplay() {
  if (!telaAcesa) return;
  oled.clearDisplay(); oled.setTextSize(1);
  if (sistemaEmModoDMX) {
    oled.setCursor(0, 0); oled.print("--- MESA DMX: 7 CHs ---");
    oled.setCursor(0, 15); oled.print("STATUS: "); oled.print(sinalDMXAtivo ? "OK" : "OFF");
    oled.setCursor(0, 30); oled.print("MODO: "); oled.print(nomesEfeitos[modoAtual]);
    oled.setCursor(0, 48); oled.setTextSize(2); oled.print("CH: "); oled.print(enderecoDMX);
  } else {
    oled.setCursor(0, 0); oled.print(dispositivoConectado ? "* APP CONECTADO *" : "--- PAINEL MANUAL ---");
    const char* s0 = (faseAtual == FASE_MODO) ? "> MODO: " : "  MODO: ";
    const char* s1 = (faseAtual == FASE_CAMPO && linhaSelecionada == 1) ? "> " : ((faseAtual == FASE_VALOR && linhaSelecionada == 1) ? ">>" : "  ");
    const char* s2 = (faseAtual == FASE_CAMPO && linhaSelecionada == 2) ? "> " : ((faseAtual == FASE_VALOR && linhaSelecionada == 2) ? ">>" : "  ");
    oled.setCursor(0, 12); oled.print(s0); oled.print(nomesEfeitos[modoAtual]);
    oled.setCursor(0, 26); oled.print(s1);
    if (modoAtual == 0) { oled.print("CANAL: CH"); oled.print(canalSelecionado + 1); } else { oled.print("VELOC: "); oled.print(velocidad); oled.print("%"); }
    oled.setCursor(0, 40); oled.print(s2);
    if (modoAtual == 0) { oled.print("BRILHO: "); oled.print(map(brilhoCanais[canalSelecionado], 0, 255, 0, 100)); } else { oled.print("BRILHO: "); oled.print(map(brilhoGeral, 0, 255, 0, 100)); }
    oled.print("%");
  }
  oled.display();
}
