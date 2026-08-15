#ifndef DISPLAY_MANAGER_H
#define DISPLAY_MANAGER_H

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "WinchConfig.h"
#include "EncoderManager.h"
#include "MotorController.h"
#include "PreferencesManager.h"
#include "rebranded_logo.h"

extern Adafruit_SSD1306 display;

class DisplayManager {
private:
  int lastClkState = HIGH;
  unsigned long ultimoDebounce = 0;

public:
  enum FasesMenu { FASE_DMX, FASE_ALTURA };
  FasesMenu faseAtual = FASE_DMX;

  void begin() {
    pinMode(ENC_CLK, INPUT_PULLUP);
    pinMode(ENC_DT, INPUT_PULLUP);
    pinMode(ENC_SW, INPUT_PULLUP);

    lastClkState = digitalRead(ENC_CLK);

    Wire.begin(8, 9);
    Wire.setClock(400000); // 400kHz Fast Mode I2C
    if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
      Serial.println("OLED ERR");
    }

    // --- EXIBE A NOVA LOGO REBRANDED 128x64 NO BOOT ---
    display.clearDisplay();
    display.drawBitmap(0, 0, REBRANDED_LOGO, LARGURA_TELA, ALTURA_TELA, WHITE);
    display.display();
    delay(3000);
  }

  void lidarComEncoderKnob() {
    int currentClkState = digitalRead(ENC_CLK);
    if (currentClkState != lastClkState && currentClkState == LOW) {
      bool subindo = digitalRead(ENC_DT) != currentClkState;

      if (motorController.isHoming) {
        motorController.isHoming = false;
        motorController.isCalibrated = true;
        Serial.println("ℹ️ HOMING CANCELADO por rotação do encoder knob.");
      }

      if (faseAtual == FASE_DMX) {
        int dmx = prefManager.dmxAddress;
        if (subindo) { dmx++; if (dmx > 512) dmx = 1; }
        else { dmx--; if (dmx < 1) dmx = 512; }
        prefManager.dmxAddress = dmx;
        Serial.print("🎛️ Novo Canal DMX: "); Serial.println(dmx);
      } else {
        double alvo = motorController.targetPosMM;
        if (subindo) {
          alvo = min(MAX_ALTURA_CABO_MM, alvo + 10.0); // 1cm por estalo
        } else {
          alvo = max(0.0, alvo - 10.0);
        }
        motorController.targetPosMM = alvo;
        Serial.print("📐 Nova Altura Alvo: "); Serial.print(alvo / 10.0); Serial.println(" cm");
      }
    }
    lastClkState = currentClkState;

    int currentSwState = digitalRead(ENC_SW);
    static int lastSwState = HIGH;
    if (currentSwState != lastSwState && currentSwState == LOW) {
      if (millis() - ultimoDebounce >= 250) {
        ultimoDebounce = millis();

        if (motorController.isHoming) {
          motorController.isHoming = false;
          motorController.isCalibrated = true;
        }

        if (faseAtual == FASE_DMX) {
          faseAtual = FASE_ALTURA;
          Serial.println("🔘 Modo alterado para: AJUSTE DE ALTURA");
        } else {
          faseAtual = FASE_DMX;
          prefManager.saveDMX(prefManager.dmxAddress);
          Serial.println("🔘 Modo alterado para: AJUSTE DE DMX (Salvo)");
        }
      }
    }
    lastSwState = currentSwState;
  }

  void atualizarOLED() {
    static unsigned long lastDraw = 0;
    static bool lastMotorMovendo = false;

    double realPos = USAR_ENCODER ? encoder.getPositionMM() : ((double)motorController.currentPosition / STEPS_PER_MM);
    bool motorMovendo = (abs(motorController.targetPosMM - realPos) > POSITION_TOLERANCE_MM) || motorController.isHoming;

    if (motorMovendo) {
      lastMotorMovendo = true;
      return;
    }

    if (lastMotorMovendo || (millis() - lastDraw >= 250)) {
      lastDraw = millis();
      lastMotorMovendo = false;

      display.clearDisplay();
      display.setTextColor(SSD1306_WHITE);

      // Cabeçalho
      display.setTextSize(1);
      display.setCursor(20, 0);
      display.print("KINETIC SYSTEM");

      display.drawFastHLine(0, 10, LARGURA_TELA, WHITE);

      if (encoder.encoderError) {
        display.fillRect(0, 14, LARGURA_TELA, 14, WHITE);
        display.setTextColor(SSD1306_BLACK);
        display.setCursor(14, 17);
        display.print("ERRO DE ENCODER!");
        display.setTextColor(SSD1306_WHITE);
      } else {
        display.setCursor(0, 16);
        if (faseAtual == FASE_DMX) display.print("> "); else display.print("  ");
        display.print("DMX Canal: "); display.print(prefManager.dmxAddress);
      }

      double realCM = realPos / 10.0;
      double alvoCM = motorController.targetPosMM / 10.0;

      // Exibição em Centímetros (cm)
      display.setCursor(0, 32);
      display.print("  REAL: ");
      display.print(realCM, 1);
      display.print(" cm");

      display.setCursor(0, 48);
      if (faseAtual == FASE_ALTURA) display.print("> "); else display.print("  ");
      display.print("ALVO: ");
      display.print(alvoCM, 1);
      display.print(" cm");

      display.display();
    }
  }
};

extern DisplayManager displayManager;

#endif // DISPLAY_MANAGER_H