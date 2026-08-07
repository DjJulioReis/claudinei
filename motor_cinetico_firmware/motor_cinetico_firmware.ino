#include <Arduino.h>
#include "WinchConfig.h"
#include "PreferencesManager.h"
#include "EncoderManager.h"
#include "MotorController.h"
#include "BLEManager.h"
#include "DisplayManager.h"

// --- INSTANCIAÇÃO GLOBAL DE CLASSES DE SUPORTE ---
PreferencesManager prefManager;
EncoderManager encoder;
MotorController motorController;
BLEManager ble;
Adafruit_SSD1306 display(LARGURA_TELA, ALTURA_TELA, &Wire, OLED_RESET);
DisplayManager displayManager;

// --- ISR DE DECODIFICAÇÃO DO ENCODER ---
void IRAM_ATTR encoderISR() {
  encoder.handleISR();
}

void setup() {
  Serial.begin(115200);
  Serial.println("MILETO KINETIC SYSTEM: INITIALIZING MAIN BOOT...");

  // Inicializa o Gerenciador de preferências locais
  prefManager.begin();

  // Inicializa o Hardware do encoder e anexa as interrupções
  encoder.begin();
  attachInterrupt(digitalPinToInterrupt(ENCODER_A), encoderISR, CHANGE);
  attachInterrupt(digitalPinToInterrupt(ENCODER_B), encoderISR, CHANGE);

  // Inicializa o Controlador de Movimento e o driver de passo
  motorController.begin();

  // --- ACIONAMENTO DO RE-RESET AUTOMÁTICO NO BOOT (HOMING INICIAL) ---
  // Força o guincho a realizar a rotina de busca de zero de forma automática ao iniciar!
  motorController.isHoming = true;
  motorController.isCalibrated = false;

  // Inicializa o display OLED e o encoder de menu (exibe a logo por 3 segundos)
  displayManager.begin();

  // Inicializa a pilha de Bluetooth Low Energy (NimBLE)
  ble.begin();

  Serial.println("🚀 MILETO KINETIC BOOT COMPLETED: WAITING FOR COMPULSORY SENSOR HOME RESET...");
}

void loop() {
  // 1. Processa comandos pendentes do BLE
  if (ble.novoComandoBle) {
    ble.processarBluetooth();
    ble.novoComandoBle = false;
    ble.comandoPendente = "";
  }

  // 2. Executa a máquina de controle de malha fechada e homing de forma assíncrona
  motorController.runClosedLoop();

  // 3. Monitora os desvios e folgas do motor com o encoder óptico para segurança
  motorController.monitorSafety();

  // 4. Trata a navegação do encoder físico e o menu do OLED
  displayManager.lidarComEncoderKnob();
  displayManager.atualizarOLED();

  // 5. Trata Handshake periódico e notificações de telemetria BT
  ble.processHandshakeAndStats();
}