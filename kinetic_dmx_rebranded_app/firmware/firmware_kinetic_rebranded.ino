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
  Serial.println("KINETIC SYSTEM: INITIALIZING MAIN BOOT...");

  // Inicializa o Gerenciador de preferências locais
  prefManager.begin();

  // Inicializa o Hardware do encoder e anexa as interrupções
  encoder.begin();
  attachInterrupt(digitalPinToInterrupt(ENCODER_A), encoderISR, CHANGE);
  attachInterrupt(digitalPinToInterrupt(ENCODER_B), encoderISR, CHANGE);

  // Inicializa o Controlador de Movimento e o driver de passo
  motorController.begin();

  // --- ACIONAMENTO DO RESET AUTOMÁTICO NO BOOT (HOMING INICIAL) ---
  motorController.isHoming = true;
  motorController.isCalibrated = false;

  // Inicializa o display OLED e exibe a nova logo 128x64 por 3 segundos
  displayManager.begin();

  // Inicializa a pilha Bluetooth Low Energy (NimBLE)
  ble.begin();

  Serial.println("🚀 KINETIC SYSTEM BOOT COMPLETED: WAITING FOR SENSOR HOME RESET...");
}

void loop() {
  // 1. Processa comandos pendentes do BLE
  if (ble.novoComandoBle) {
    ble.processarBluetooth();
    ble.novoComandoBle = false;
    ble.comandoPendente = "";
  }

  // 2. Executa a máquina de controle de movimento e homing de forma assíncrona
  motorController.runClosedLoop();

  // 3. Monitora os desvios do motor para segurança física (se USAR_ENCODER estiver ativo)
  motorController.monitorSafety();

  // 4. Trata a navegação do encoder físico e a renderização otimizada do OLED
  displayManager.lidarComEncoderKnob();
  displayManager.atualizarOLED();

  // 5. Trata Handshake e notificações de telemetria BT
  ble.processHandshakeAndStats();
}