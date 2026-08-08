#ifndef DISPLAY_MANAGER_H
#define DISPLAY_MANAGER_H

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "WinchConfig.h"
#include "EncoderManager.h"
#include "MotorController.h"
#include "PreferencesManager.h"
#include "MILETO_LOGO_1.h"

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
    if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
      Serial.println("OLED ERR");
    }

    // --- EXIBE A LOGO OFICIAL DA MILETO NO CORPO DO BOOT ---
    display.clearDisplay();
    display.drawBitmap(0, 0, MILETO_LOGO_1, LARGURA_TELA, ALTURA_TELA, WHITE);
    display.display();
    delay(3000); // 3 segundos com a logo
  }

  void lidarComEncoderKnob() {
    int currentClkState = digitalRead(ENC_CLK);
    if (currentClkState != lastClkState && currentClkState == LOW) {
      bool subindo = digitalRead(ENC_DT) != currentClkState;
      if (faseAtual == FASE_DMX) {
        int dmx = prefManager.dmxAddress;
        if (subindo) { dmx++; if (dmx > 512) dmx = 1; }
        else { dmx--; if (dmx < 1) dmx = 512; }
        prefManager.dmxAddress = dmx;
      } else {
        double alvo = motorController.targetPosMM;
        if (subindo) {
          alvo = min(MAX_ALTURA_CABO_MM, alvo + 5.0);
        } else {
          alvo = max(0.0, alvo - 5.0);
        }
        motorController.targetPosMM = alvo;

        // Se o usuário ajustar a altura pelo knob físico, cancela o homing e assume calibração
        if (motorController.isHoming) {
          motorController.isHoming = false;
          motorController.isCalibrated = true;
          Serial.println("ℹ️ HOMING CANCELADO pelo knob giratório físico.");
        }
      }
    }
    lastClkState = currentClkState;

    int currentSwState = digitalRead(ENC_SW);
    static int lastSwState = HIGH;
    if (currentSwState != lastSwState && currentSwState == LOW) {
      if (millis() - ultimoDebounce >= 250) {
        ultimoDebounce = millis();
        if (faseAtual == FASE_DMX) {
          faseAtual = FASE_ALTURA;
        } else {
          faseAtual = FASE_DMX;
          prefManager.saveDMX(prefManager.dmxAddress);
        }
      }
    }
    lastSwState = currentSwState;
  }

  void atualizarOLED() {
    static unsigned long lastDraw = 0;
    if (millis() - lastDraw >= 200) {
      lastDraw = millis();
      display.clearDisplay();
      display.setTextSize(1);
      display.setTextColor(SSD1306_WHITE);
      display.setCursor(0, 0);
      display.print("--- GUINCHO KINETIC ---");

      display.setCursor(0, 16);
      if (faseAtual == FASE_DMX) display.print("> "); else display.print("  ");
      display.print("DMX CH: "); display.print(prefManager.dmxAddress);

      // Diagnóstico do Encoder Óptico no OLED
      display.setCursor(72, 16);
      if (encoder.encoderError) {
        display.print("ERR ENC!");
      } else {
        display.print("E:"); display.print(encoder.getCount());
      }

      display.setCursor(0, 32);
      display.print("ALTURA REAL: "); display.print(encoder.getPositionMM(), 1); display.print(" mm");

      display.setCursor(0, 48);
      if (faseAtual == FASE_ALTURA) display.print("> "); else display.print("  ");
      display.print("ALTURA ALVO: "); display.print(motorController.targetPosMM, 1); display.print(" mm");
      display.display();
    }
  }
};

extern DisplayManager displayManager;

#endif // DISPLAY_MANAGER_H