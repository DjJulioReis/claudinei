#ifndef BLE_MANAGER_H
#define BLE_MANAGER_H

#include <NimBLEDevice.h>
#include "WinchConfig.h"
#include "EncoderManager.h"
#include "MotorController.h"
#include "PreferencesManager.h"

// --- SERVER CALLBACKS DECLARATION ---
class MyServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pS, NimBLEConnInfo& connInfo) override;
    void onDisconnect(NimBLEServer* pS, NimBLEConnInfo& connInfo, int reason) override;
};

// --- CHARACTERISTIC CALLBACKS DECLARATION ---
class MyCharCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *pC, NimBLEConnInfo& connInfo) override;
};

class BLEManager {
private:
  NimBLEServer* pServer = NULL;

public:
  NimBLECharacteristic* pTxCharacteristic = NULL;
  bool dispositivoConectado = false;
  bool autenticado = false;
  uint32_t desafioHandshake = 0;
  String comandoPendente = "";
  bool novoComandoBle = false;

  void begin() {
    NimBLEDevice::init("MILETO");
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    pServer = NimBLEDevice::createServer();

    // Configura os callbacks do servidor
    pServer->setCallbacks(new MyServerCallbacks());

    NimBLEService *pService = pServer->createService(SERVICE_UUID);
    pTxCharacteristic = pService->createCharacteristic(TX_UUID, NIMBLE_PROPERTY::NOTIFY);

    NimBLECharacteristic *pRxCharacteristic = pService->createCharacteristic(RX_UUID, NIMBLE_PROPERTY::WRITE);
    pRxCharacteristic->setCallbacks(new MyCharCallbacks());

    pService->start();

    NimBLEDevice::setOwnAddrType(BLE_OWN_ADDR_RANDOM);
    NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
    BLEAdvertisementData mainAdv;
    mainAdv.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    mainAdv.setCompleteServices(BLEUUID(SERVICE_UUID));
    mainAdv.setName("MILETO");
    pAdvertising->setAdvertisementData(mainAdv);
    pAdvertising->start();
  }

  void processHandshakeAndStats() {
    static unsigned long lastAuthReq = 0;
    if (dispositivoConectado && !autenticado && millis() - lastAuthReq >= 2000) {
      lastAuthReq = millis();
      String msg = "AUTH_CHALLENGE:" + String(desafioHandshake) + "\n";
      pTxCharacteristic->setValue(msg.c_str());
      pTxCharacteristic->notify();
    }

    if (dispositivoConectado && autenticado) {
      // Monitora erros de segurança e notifica o app
      if (encoder.encoderError) {
        static unsigned long lastErrNotify = 0;
        if (millis() - lastErrNotify >= 1000) {
          lastErrNotify = millis();
          pTxCharacteristic->setValue("ERROR:ENCODER_DESYNC\n");
          pTxCharacteristic->notify();
        }
      } else {
        enviarEstatisticasBT();
      }
    }
  }

  void enviarEstatisticasBT() {
    static unsigned long last = 0;
    if (millis() - last >= 100) {
      last = millis();
      char buf[120];

      double realPos = USAR_ENCODER ? encoder.getPositionMM() : ((double)motorController.currentPosition / STEPS_PER_MM);
      long encCount = USAR_ENCODER ? encoder.getCount() : (long)((double)motorController.currentPosition / STEPS_PER_MM * (ENCODER_PULSES * QUADRATURE_FACTOR));

      // STATS:isCalibrated,isHoming,currentPosition,targetPosition,0,0,currentPosMM,targetPosMM,0,stepsDeviation,encoderCount
      sprintf(buf, "STATS:%d,%d,%d,%d,0,0,%.1f,%.1f,0,%d,%ld\n",
              motorController.isCalibrated ? 1 : 0,
              motorController.isHoming ? 1 : 0,
              motorController.currentPosition,
              (int)(motorController.targetPosMM * STEPS_PER_MM),
              realPos,
              motorController.targetPosMM,
              USAR_ENCODER ? (motorController.currentPosition - (int)encoder.getCount()) : 0,
              encCount);
      pTxCharacteristic->setValue(buf);
      pTxCharacteristic->notify();
    }
  }

  void processarBluetooth() {
    comandoPendente.replace("\n", "");
    comandoPendente.replace("\r", "");
    comandoPendente.trim();

    int div = comandoPendente.indexOf(':');
    if (div == -1) return;

    String cmd = comandoPendente.substring(0, div);
    String val = comandoPendente.substring(div + 1);
    int iv = val.toInt();

    if (cmd == "AUTH_RESPONSE") {
      if (iv == (desafioHandshake * 2) + 7) {
        autenticado = true;
        pTxCharacteristic->setValue("MILETO_AUTH:VALID\nCONNECTED_OK\n");
        pTxCharacteristic->notify();
        delay(200);
        executarVarreduraRDM();
      } else {
        autenticado = false;
        pTxCharacteristic->setValue("MILETO_AUTH:INVALID\n");
        pTxCharacteristic->notify();
      }
      return;
    }

    if (!autenticado) return;

    if (cmd == "SET_POS") {
      if (!encoder.encoderError) {
        // O valor enviado pelo aplicativo é em milímetros escalados por STEPS_PER_MM
        double alvoMM = (double)iv / STEPS_PER_MM;
        motorController.targetPosMM = constclampedMM(alvoMM);

        // Se o usuário ajustar a posição manualmente pelo aplicativo, cancela o homing e assume calibração
        if (motorController.isHoming) {
          motorController.isHoming = false;
          motorController.isCalibrated = true;
          Serial.println("ℹ️ HOMING CANCELADO por comando SET_POS do aplicativo.");
        }
      }
    }
    else if (cmd == "CALIBRAR") {
      motorController.isHoming = true;
      motorController.isCalibrated = false;
      encoder.encoderError = false;
    }
    else if (cmd == "PARAR") {
      motorController.stop();
    }
    else if (cmd == "GRAVAR") {
      prefManager.saveDMX(prefManager.dmxAddress);
      pTxCharacteristic->setValue("GRAVAR:OK\n");
      pTxCharacteristic->notify();
    }
    else if (cmd == "VARREDURA_RDM") {
      executarVarreduraRDM();
    }
  }

  double constclampedMM(double val) {
    if (val < 0.0) return 0.0;
    if (val > MAX_ALTURA_CABO_MM) return MAX_ALTURA_CABO_MM;
    return val;
  }

  void executarVarreduraRDM() {
    if (!dispositivoConectado || !autenticado) return;

    pTxCharacteristic->setValue("RDM_START\n");
    pTxCharacteristic->notify();
    delay(100);

    // Assinatura única do guincho/motor cinético
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    uint32_t dev_id = ((uint32_t)mac[2] << 24) |
                        ((uint32_t)mac[3] << 16) |
                        ((uint32_t)mac[4] << 8)  |
                        (uint32_t)mac[5];
    char buf[60];
    sprintf(buf, "RDM_DEV:4d49,%08X,%d,4,GUINCHO_KINETIC_4CH\n", dev_id, prefManager.dmxAddress);
    pTxCharacteristic->setValue(buf);
    pTxCharacteristic->notify();
    delay(100);

    pTxCharacteristic->setValue("RDM_END\n");
    pTxCharacteristic->notify();
    delay(100);
  }
};

extern BLEManager ble;

// --- INLINE DEFINITIONS FOR STANDALONE CALLBACKS ---
inline void MyServerCallbacks::onConnect(NimBLEServer* pS, NimBLEConnInfo& connInfo) {
    ble.dispositivoConectado = true;
    ble.autenticado = false;
    randomSeed(micros());
    ble.desafioHandshake = random(1000, 9999);
    pS->updateConnParams(connInfo.getConnHandle(), 16, 32, 0, 400);
}

inline void MyServerCallbacks::onDisconnect(NimBLEServer* pS, NimBLEConnInfo& connInfo, int reason) {
    ble.dispositivoConectado = false;
    ble.autenticado = false;
    NimBLEDevice::startAdvertising();
}

inline void MyCharCallbacks::onWrite(NimBLECharacteristic *pC, NimBLEConnInfo& connInfo) {
    String rxValue = pC->getValue();
    if (rxValue.length() > 0) {
      ble.comandoPendente = rxValue;
      ble.novoComandoBle = true;
    }
}

#endif // BLE_MANAGER_H