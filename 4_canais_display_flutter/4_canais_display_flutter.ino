#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include "BluetoothSerial.h"
#include "SSD1306Ascii.h"
#include "SSD1306AsciiWire.h"

// Driver nativo do ESP32 para UART (DMX sem biblioteca externa)
#include "driver/uart.h"

// Bibliotecas nativas do ESP32 para controle de estabilidade de hardware
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// --- INCLUSÃO DA LOGO CUSTOMIZADA ---
#include "MILETO_LOGO_1.h"

#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error O Bluetooth nao esta ativado!
#endif

SSD1306AsciiWire oled;
Preferences preferences;
BluetoothSerial SerialBT;

// --- CONFIGURAÇÃO DA UART NATIVA PARA DMX512 ---
#define DMX_UART_NUM UART_NUM_2  // Usa a UART2 do ESP32
#define DMX_RX_PIN 16            // Pino RX conectado ao MAX485
#define DMX_TX_PIN 17            // Pino TX (Obrigatório instanciar no driver)

static QueueHandle_t dmx_queue;  // Fila de eventos de hardware
uint8_t raw_dmx_buf[515];        // Buffer para armazenar o frame (Start Code + 512 canais)
int dmx_idx = 0;                 // Ponteiro do canal atual recebido
bool dmx_em_frame = false;       // Flag de sincronismo após o BREAK

// --- MAPEAMENTO DE PINOS DOS MOSFETS ---
#define MOSFET_CH1 12
#define MOSFET_CH2 13
#define MOSFET_CH3 14
#define MOSFET_CH4 27

// LED de Status Onboard (Azul do STM32/ESP32)
#define LED_STATUS_DMX 2

// Painel de Controle Físico
#define BTN_MUDAR_CAMPO 25  // Botão 1: VOLTAR / CANCELAR
#define BTN_FRENTE 33       // Botão 2: Sobe / Mais (+)
#define BTN_VOLTA 32        // Botão 3: Desce / Menos (-)
#define BTN_GRAVAR 26       // Botão 4: Avançar / OK / Confirmar Escolha
#define CHAVE_DMX_MANUAL 4  // Botão de Pulso: Alterna entre Manual / Mesa DMX

#define PWM_FREQ 4000
#define PWM_RES 8

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

// --- CONTROLE DE TIMEOUT E SINAL DMX ---
unsigned long ultimoPacoteDMX = 0;
bool sinalDMXAtivo = false;

unsigned long ultimoPiscaStatus = 0;
bool estadoLedStatus = false;
bool dispositivoConectado = false;

// --- DECLARAÇÃO DE FUNÇÕES ---
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
  // 1. DESATIVAR DETECTOR DE BROWNOUT
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  Serial.begin(115200);
  delay(500);
  Serial.println("\n====================================");
  Serial.println("   MILETO - FIRMWARE ESP32 V5.1     ");
  Serial.println("====================================");

  // Inicializa o Pino do LED de Status
  pinMode(LED_STATUS_DMX, OUTPUT);
  digitalWrite(LED_STATUS_DMX, LOW);

  // Inicializa os Pinos de Controle Físico
  pinMode(BTN_MUDAR_CAMPO, INPUT_PULLUP);
  pinMode(BTN_FRENTE, INPUT_PULLUP);
  pinMode(BTN_VOLTA, INPUT_PULLUP);
  pinMode(BTN_GRAVAR, INPUT_PULLUP);
  pinMode(CHAVE_DMX_MANUAL, INPUT_PULLUP);

  // Ativa PWM em todos os 4 canais de MOSFET permanentemente
  ledcAttach(MOSFET_CH1, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH2, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH3, PWM_FREQ, PWM_RES);
  ledcAttach(MOSFET_CH4, PWM_FREQ, PWM_RES);

  // Inicializa Barramento I2C e OLED
  Wire.begin(21, 22);
  Wire.setClock(400000L);

  oled.begin(&Adafruit128x64, 0x3C);
  oled.setFont(Adafruit5x7);

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
  uart_set_pin(DMX_UART_NUM, DMX_TX_PIN, DMX_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  uart_driver_install(DMX_UART_NUM, 1024, 0, 20, &dmx_queue, 0);

  SerialBT.begin("MILETO");
  tempoUltimaAtividade = millis();

  atualizarDisplay();
}

void loop() {
  // --- CONTROLE DE STATUS DO LED AZUL (SINAL DMX / BLUETOOTH) ---
  if (sistemaEmModoDMX) {
    sinalDMXAtivo = (millis() - ultimoPacoteDMX < 1000);

    if (sinalDMXAtivo) {
      if (millis() - ultimoPiscaStatus >= 70) {
        ultimoPiscaStatus = millis();
        estadoLedStatus = !estadoLedStatus;
        digitalWrite(LED_STATUS_DMX, estadoLedStatus ? HIGH : LOW);
      }
    } else {
      digitalWrite(LED_STATUS_DMX, LOW);
    }
  } else if (!dispositivoConectado) {
    if (millis() - ultimoPiscaStatus >= 200) {
      ultimoPiscaStatus = millis();
      estadoLedStatus = !estadoLedStatus;
      digitalWrite(LED_STATUS_DMX, estadoLedStatus ? HIGH : LOW);
    }
  } else {
    digitalWrite(LED_STATUS_DMX, HIGH);
  }

  // --- LÓGICA DO BOTÃO DMX (BOTÃO DE PULSO ALTERNADOR) ---
  if (digitalRead(CHAVE_DMX_MANUAL) == LOW) {
    delay(50);
    if (digitalRead(CHAVE_DMX_MANUAL) == LOW) {
      if (millis() - ultimoDebounce >= 250) {
        ultimoDebounce = millis();
        acordaTela();

        sistemaEmModoDMX = !sistemaEmModoDMX;

        // Ao sair do modo DMX, restaura configurações salvas para evitar interferência
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
          SerialBT.print("CHAVE_MODO:");
          SerialBT.println(sistemaEmModoDMX ? "DMX" : "RF");
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
          } else if (faseAtual == FASE_CAMPO) {
            faseAtual = FASE_VALOR;
          } else if (faseAtual == FASE_VALOR) {
            oled.clear();
            oled.write("\n\n   GRAVANDO...\n");
            oled.write("   MEMORIA FLASH OK");

            salvarConfiguracao();
            delay(700);

            faseAtual = FASE_MODO;
            linhaSelecionada = 0;
          }

          atualizarDisplay();
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
          oled.clear();
          oled.write("\n\n   GRAVANDO...\n");
          oled.write("   DMX GRAVADO OK");
          salvarConfiguracao();
          delay(700);
          atualizarDisplay();
          while (digitalRead(BTN_GRAVAR) == LOW) { delay(10); }
        }
      }
    }
  }

  // --- ECONOMIA DE TELA ---
  if (telaAcesa && (millis() - tempoUltimaAtividade >= TEMPO_SLEEP_TELA)) {
    oled.clear();
    oled.ssd1306WriteCmd(SSD1306_DISPLAYOFF);
    telaAcesa = false;
  }

  receberDadosBluetooth();

  if (sistemaEmModoDMX) {
    processarMesaDMX();
  }

  executarEfeitos();
}

void desenharLogo(const uint8_t* bitmap) {
  oled.clear();
  for (uint8_t pagina = 0; pagina < 8; pagina++) {
    oled.setCursor(0, pagina);
    for (uint8_t coluna = 0; coluna < 128; coluna++) {
      oled.ssd1306WriteRam(pgm_read_byte(&bitmap[pagina * 128 + coluna]));
    }
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
  static unsigned long ultimoEnvioNiveis = 0;
  if (dispositivoConectado && millis() - ultimoEnvioNiveis >= 60) {
    ultimoEnvioNiveis = millis();
    SerialBT.print("CH_LEVELS:");
    SerialBT.print(map(niveisAtuais[0], 0, 255, 0, 100)); SerialBT.print(",");
    SerialBT.print(map(niveisAtuais[1], 0, 255, 0, 100)); SerialBT.print(",");
    SerialBT.print(map(niveisAtuais[2], 0, 255, 0, 100)); SerialBT.print(",");
    SerialBT.println(map(niveisAtuais[3], 0, 255, 0, 100));
  }
}

void executarEfeitos() {
  unsigned long tempoAtual = millis();
  int delayEfeito = map(velocidad, 0, 100, 800, 25);

  // --- MODO MANUAL: PISCADA INDEPENDENTE DINÂMICA ---
  if (modoAtual == 0) {
    static unsigned long ultimosTempos[4] = {0, 0, 0, 0};
    static boolean estadosCanais[4] = {false, false, false, false};
    int delaysIndividuais[4];

    for (int i = 0; i < 4; i++) {
      if (velocidadesCanais[i] >= 100) {
        // Velocidade máxima para este canal = estático
        delaysIndividuais[i] = 0;
        estadosCanais[i] = true;
      } else {
        // Mapeia velocidade (0-99) para delay (800ms a 40ms)
        delaysIndividuais[i] = map(velocidadesCanais[i], 0, 99, 800, 40);

        // Mantém a influência do brilho na velocidade se desejar, ou remove para controle puro
        // Aqui removemos para o controle ser 100% manual via slider de velocidade
        if (tempoAtual - ultimosTempos[i] >= (unsigned long)delaysIndividuais[i]) {
          ultimosTempos[i] = tempoAtual;
          estadosCanais[i] = !estadosCanais[i];
        }
      }

      int nivelBase = (brilhoCanais[i] * brilhoGeral) / 255;
      writeChannel(i, estadosCanais[i] ? nivelBase : 0);
    }
    enviarNiveisBT();
    return;
  }

  // 2. TRAVA DE SEGURANÇA PARA OS MODOS DE EFEITO (MODOS 1 A 4)
  if (brilhoGeral == 0) {
    writeChannel(0, 0);
    writeChannel(1, 0);
    writeChannel(2, 0);
    writeChannel(3, 0);
    enviarNiveisBT();
    return;
  }

  // 3. PROCESSAMENTO DOS EFEITOS AUTOMÁTICOS (MODOS 1 A 4)
  switch (modoAtual) {
    case 1:  // FADE
      if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito / 4) {
        ultimaAtualizacaoEfeito = tempoAtual;
        if (fadeDirection) fadeValue += 5;
        else fadeValue -= 5;
        if (fadeValue >= 255 || fadeValue <= 0) fadeDirection = !fadeDirection;

        writeChannel(0, (fadeValue * brilhoGeral) / 255);
        writeChannel(1, ((255 - fadeValue) * brilhoGeral) / 255);
        writeChannel(2, ((255 - fadeValue) * brilhoGeral) / 255);
        writeChannel(3, (fadeValue * brilhoGeral) / 255);
      }
      break;

    case 2:  // STROBO GERAL
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
          int intensidade = estadoStrobo ? brilhoGeral : 0;
          writeChannel(0, intensidade);
          writeChannel(1, intensidade);
          writeChannel(2, intensidade);
          writeChannel(3, intensidade);
        }
      }
      break;

    case 3:  // SEQUENCIAL
      if (tempoAtual - ultimaAtualizacaoEfeito >= (unsigned long)delayEfeito) {
        ultimaAtualizacaoEfeito = tempoAtual;
        passoAlternado = (passoAlternado + 1) % 4;
        writeChannel(0, (passoAlternado == 0) ? brilhoGeral : 0);
        writeChannel(1, (passoAlternado == 1) ? brilhoGeral : 0);
        writeChannel(2, (passoAlternado == 2) ? brilhoGeral : 0);
        writeChannel(3, (passoAlternado == 3) ? brilhoGeral : 0);
      }
      break;

    case 4:  // FIXO
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

            if (dmx_idx >= (enderecoDMX + 6)) {
              if (raw_dmx_buf[0] == 0x00) {
                ultimoPacoteDMX = millis();

                int idx = enderecoDMX;
                int dmxCH1 = raw_dmx_buf[idx + 0];
                int dmxCH2 = raw_dmx_buf[idx + 1];
                int dmxCH3 = raw_dmx_buf[idx + 2];
                int dmxCH4 = raw_dmx_buf[idx + 3];
                int dmxCH5 = raw_dmx_buf[idx + 4];
                int dmxCH6 = raw_dmx_buf[idx + 5];

                if (dmxCH6 <= 50) modoAtual = 0;
                else if (dmxCH6 <= 100) modoAtual = 1;
                else if (dmxCH6 <= 150) modoAtual = 2;
                else if (dmxCH6 <= 200) modoAtual = 3;
                else modoAtual = 4;

                velocidad = map(dmxCH5, 0, 255, 0, 100);

                // MAPEAMENTO DMX FINAL (CORRIGIDO):
                // CH1: Dimmer Saída 1
                // CH2: Dimmer Saída 2
                // CH3: Dimmer Saída 3
                // CH4: Dimmer Saída 4
                // CH5: Velocidade
                // CH6: Dimmer Geral + Seletor de Efeitos

                // Ranges do CH6:
                // 000 - 050: MANUAL (CH1-4 ativos, CH6 é Dimmer Geral 0-100%)
                // 051 - 100: FADE (CH1-4 ignorados, CH6 é Dimmer Geral 0-100%)
                // 101 - 150: STROBO (CH1-4 ignorados, CH6 é Dimmer Geral 0-100%)
                // 151 - 200: SEQUENCIAL (CH1-4 ignorados, CH6 é Dimmer Geral 0-100%)
                // 201 - 255: FIXO (CH1-4 ignorados, CH6 é Dimmer Geral 0-100%)

                if (dmxCH6 <= 50) {
                  modoAtual = 0; // Manual
                  brilhoGeral = map(dmxCH6, 0, 50, 0, 255);
                  brilhoCanais[0] = dmxCH1;
                  brilhoCanais[1] = dmxCH2;
                  brilhoCanais[2] = dmxCH3;
                  brilhoCanais[3] = dmxCH4;
                } else if (dmxCH6 <= 100) {
                  modoAtual = 1; // Fade
                  brilhoGeral = map(dmxCH6, 51, 100, 0, 255);
                } else if (dmxCH6 <= 150) {
                  modoAtual = 2; // Strobo
                  brilhoGeral = map(dmxCH6, 101, 150, 0, 255);
                } else if (dmxCH6 <= 200) {
                  modoAtual = 3; // Sequencial
                  brilhoGeral = map(dmxCH6, 151, 200, 0, 255);
                } else {
                  modoAtual = 4; // Fixo
                  brilhoGeral = map(dmxCH6, 201, 255, 0, 255);
                }
                // acordaTela(); // Não acordar a tela a cada pacote DMX para evitar flickering e lentidão
                // atualizarDisplay(); // O endereço DMX não muda com os dados, não precisa redesenhar o OLED aqui
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
    acordaTela();
    if (!dispositivoConectado) {
      dispositivoConectado = true;
      SerialBT.println("CONNECTED_OK");
    }

    // Lê o pacote até o fim da linha
    String pacoteString = SerialBT.readStringUntil('\n');
    pacoteString.trim();  // Remove espaços, \r e \n do início e fim

    if (pacoteString.length() > 0) {
      Serial.print("Recebido via BT: ");  // Debug no Monitor Serial do PC
      Serial.println(pacoteString);

      processarComandoApp(pacoteString);
      atualizarDisplay();  // Força o OLED a mostrar os novos valores na hora
    }
  }

  if (dispositivoConectado && !SerialBT.hasClient()) {
    dispositivoConectado = false;
    atualizarDisplay();
  }
}

void processarComandoApp(String pacote) {
  int divisorIndex = pacote.indexOf(':');
  if (divisorIndex == -1) return;

  String comando = pacote.substring(0, divisorIndex);
  String valor = pacote.substring(divisorIndex + 1);

  comando.trim();
  valor.trim();

  bool comandoReconhecido = true;

  // --- CONTROLE DE MODOS E PARÂMETROS GERAIS ---
  if (comando == "CHAVE_MODO") {
    sistemaEmModoDMX = (valor == "DMX");
  } else if (comando == "SET_MODO") {
    modoAtual = valor.toInt();
  } else if (comando == "SET_VEL") {
    velocidad = valor.toInt();
  } else if (comando == "SET_DIM") {
    brilhoGeral = map(valor.toInt(), 0, 100, 0, 255);
  } else if (comando == "SET_DMX") {
    enderecoDMX = valor.toInt();
  }

  // --- CONTROLE DIRETO DOS 4 CANAIS MANUAIS VIA APP ---
  else if (comando == "SET_CH1") {
    brilhoCanais[0] = map(valor.toInt(), 0, 100, 0, 255);
  } else if (comando == "SET_CH2") {
    brilhoCanais[1] = map(valor.toInt(), 0, 100, 0, 255);
  } else if (comando == "SET_CH3") {
    brilhoCanais[2] = map(valor.toInt(), 0, 100, 0, 255);
  } else if (comando == "SET_CH4") {
    brilhoCanais[3] = map(valor.toInt(), 0, 100, 0, 255);
  } else if (comando == "SET_VCH1") {
    velocidadesCanais[0] = valor.toInt();
  } else if (comando == "SET_VCH2") {
    velocidadesCanais[1] = valor.toInt();
  } else if (comando == "SET_VCH3") {
    velocidadesCanais[2] = valor.toInt();
  } else if (comando == "SET_VCH4") {
    velocidadesCanais[3] = valor.toInt();
  }

  // --- CONTROLE DE DISPARO DA PISTA VIA APP ---
  else if (comando == "EFEITO_PISTA") {
    if (valor == "START") {
      modoAtual = 3;  // Força o sequencial
    } else if (valor == "CLEAR") {
      modoAtual = 0;  // Força a volta para o modo manual
    }
  } else if (comando == "GET_CAPABILITIES") {
    SerialBT.println("CAPS:MANUAL,FADE,STROBO,SEQUENC,FIXO");
  } else if (comando == "GRAVAR") {
    salvarConfiguracao();
    SerialBT.println("GRAVAR:OK");
  } else {
    comandoReconhecido = false;
  }

  // Envia um feedback para o aplicativo Flutter depurar
  if (dispositivoConectado && comandoReconhecido) {
    SerialBT.print("ACK_");
    SerialBT.print(comando);
    Serial.println(":OK");
  }
}

void acordaTela() {
  tempoUltimaAtividade = millis();
  if (!telaAcesa) {
    oled.ssd1306WriteCmd(SSD1306_DISPLAYON);
    telaAcesa = true;
  }
}

void salvarConfiguracao() {
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
}

void imprimeNumero(int num) {
  if (num == 0) {
    oled.write('0');
    return;
  }
  char buf[5];
  int i = 0;
  while (num > 0) {
    buf[i++] = (num % 10) + '0';
    num /= 10;
  }
  while (i > 0) { oled.write(buf[--i]); }
}

void atualizarDisplay() {
  if (!telaAcesa) return;
  oled.clear();

  if (sistemaEmModoDMX) {
    oled.write("   --- MESA DMX ---\n\n");
    oled.write(" CANAL: ");
    imprimeNumero(enderecoDMX);
  } else {
    oled.write(dispositivoConectado ? "   --- BT APP ---\n" : "   - PAINEL RF -\n");

    const char* setaL0 = "  ";
    const char* setaL1 = "  ";
    const char* setaL2 = "  ";

    if (faseAtual == FASE_MODO) {
      setaL0 = "> ";
    } else if (faseAtual == FASE_CAMPO) {
      if (linhaSelecionada == 1) setaL1 = "> ";
      if (linhaSelecionada == 2) setaL2 = "> ";
    } else if (faseAtual == FASE_VALOR) {
      if (linhaSelecionada == 1) setaL1 = ">>";
      if (linhaSelecionada == 2) setaL2 = ">>";
    }

    oled.write(setaL0);
    oled.write("MODO: ");
    oled.write(nomesEfeitos[modoAtual]);
    oled.write("\n");

    oled.write(setaL1);
    if (modoAtual == 0) {
      oled.write("CANAL: CH");
      imprimeNumero(canalSelecionado + 1);
    } else {
      oled.write("VEL: ");
      imprimeNumero(velocidad);
      oled.write("%");
    }
    oled.write("\n");

    oled.write(setaL2);
    if (modoAtual == 0) {
      oled.write("DIM CH: ");
      imprimeNumero(map(brilhoCanais[canalSelecionado], 0, 255, 0, 100));
    } else {
      oled.write("DIM GERAL: ");
      imprimeNumero(map(brilhoGeral, 0, 255, 0, 100));
    }
    oled.write("%");
  }
}