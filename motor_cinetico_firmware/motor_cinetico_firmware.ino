#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Preferences.h>
#include "esp_mac.h"
#include <NimBLEDevice.h>

#define LARGURA_TELA 128
#define ALTURA_TELA 64
#define OLED_RESET -1
Adafruit_SSD1306 display(LARGURA_TELA, ALTURA_TELA, &Wire, OLED_RESET);

// --- PINOS EXCLUSIVOS DO MOTOR/GUINCHO CINÉTICO ESP32-C3 ---
#define STEP_PIN 0      // Sinal de Passo do Driver do Motor
#define DIR_PIN  1      // Sinal de Direção do Driver do Motor
#define EN_PIN   2      // Enable do Driver do Motor
#define SENSOR_HOME 4   // Sensor Óptico/Fim de curso para Calibração (Zero)

#define ENC_CLK 6
#define ENC_DT   7
#define ENC_SW  10

// --- VARIÁVEIS DE PROGRAMAÇÃO E TELEMETRIA DO MOTOR ---
bool isCalibrated = false;
bool isHoming = false;
int currentPosition = 0;   // Em passos do motor
int targetPosition = 0;    // Em passos do motor
double currentPosMM = 0.0; // Posição em mm (0 a 400mm)
double targetPosMM = 0.0;  // Posição em mm (0 a 400mm)
int stepsDeviation = 0;
int dmxAddress = 1;

static const double stepsPerMM = 40.0; // 16000 passos = 400mm de curso útil
static const double maxAlturaCaboMM = 400.0;

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

uint32_t obterDeviceIDUnico() {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  uint32_t deviceID = ((uint32_t)mac[2] << 24) |
                      ((uint32_t)mac[3] << 16) |
                      ((uint32_t)mac[4] << 8)  |
                      (uint32_t)mac[5];
  return deviceID;
}

void executarVarreduraRDM() {
  if (!dispositivoConectado || !autenticado) return;

  pTxCharacteristic->setValue("RDM_START\n");
  pTxCharacteristic->notify();
  delay(100);

  // Assinatura única do guincho/motor cinético
  uint32_t dev_id = obterDeviceIDUnico();
  char buf[60];
  sprintf(buf, "RDM_DEV:4d49,%08X,%d,4,GUINCHO_KINETIC_4CH\n", dev_id, dmxAddress);
  pTxCharacteristic->setValue(buf);
  pTxCharacteristic->notify();
  delay(100);

  pTxCharacteristic->setValue("RDM_END\n");
  pTxCharacteristic->notify();
  delay(100);
}

void enviarEstatisticasBT() {
  static unsigned long last = 0;
  if (dispositivoConectado && autenticado && millis() - last >= 100) {
    last = millis();
    // STATS:isCalibrated,isHoming,currentPosition,targetPosition,0,0,currentPosMM,targetPosMM,0,stepsDeviation
    char buf[100];
    sprintf(buf, "STATS:%d,%d,%d,%d,0,0,%.1f,%.1f,0,%d\n",
            isCalibrated ? 1 : 0,
            isHoming ? 1 : 0,
            currentPosition,
            targetPosition,
            currentPosMM,
            targetPosMM,
            stepsDeviation);
    pTxCharacteristic->setValue(buf);
    pTxCharacteristic->notify();
  }
}

// Controle físico de movimentação dos pulsos do Motor de Passo (Kinetic)
void gerarPulsoPasso(bool direcaoSubida) {
  digitalWrite(DIR_PIN, direcaoSubida ? HIGH : LOW);
  digitalWrite(STEP_PIN, HIGH);
  delayMicroseconds(400); // Freqüência do pulso
  digitalWrite(STEP_PIN, LOW);
  delayMicroseconds(400);

  if (direcaoSubida) {
    currentPosition++;
  } else {
    currentPosition = max(0, currentPosition - 1);
  }
  currentPosMM = (double)currentPosition / stepsPerMM;
}

void processarBluetooth() {
  comandoPendente.replace("\n", ""); comandoPendente.replace("\r", ""); comandoPendente.trim();
  int div = comandoPendente.indexOf(':'); if (div == -1) return;
  String cmd = comandoPendente.substring(0, div); String val = comandoPendente.substring(div + 1);
  int iv = val.toInt();

  if (cmd == "AUTH_RESPONSE") {
    if (iv == (desafioHandshake * 2) + 7) {
      autenticado = true;
      pTxCharacteristic->setValue("MILETO_AUTH:VALID\nCONNECTED_OK\n"); pTxCharacteristic->notify();
      delay(200);
      executarVarreduraRDM();
    } else {
      autenticado = false;
      pTxCharacteristic->setValue("MILETO_AUTH:INVALID\n"); pTxCharacteristic->notify();
    }
    return;
  }
  if (!autenticado) return;

  if (cmd == "SET_POS") {
    targetPosition = iv;
    targetPosMM = (double)targetPosition / stepsPerMM;
  }
  else if (cmd == "CALIBRAR") {
    isHoming = true;
    isCalibrated = false;
  }
  else if (cmd == "PARAR") {
    targetPosition = currentPosition;
    targetPosMM = currentPosMM;
    isHoming = false;
  }
  else if (cmd == "GRAVAR") {
    preferences.begin("mileto_cfg", false);
    preferences.putInt("dmx", dmxAddress);
    preferences.end();
    pTxCharacteristic->setValue("GRAVAR:OK\n"); pTxCharacteristic->notify();
  }
}

int lastClkState;
unsigned long ultimoDebounce = 0;
enum FasesMenu { FASE_DMX, FASE_ALTURA };
FasesMenu faseAtual = FASE_DMX;

void lidarComEncoder() {
  int currentClkState = digitalRead(ENC_CLK);
  if (currentClkState != lastClkState && currentClkState == LOW) {
    bool subindo = digitalRead(ENC_DT) != currentClkState;
    if (faseAtual == FASE_DMX) {
      if (subindo) { dmxAddress++; if (dmxAddress > 512) dmxAddress = 1; }
      else { dmxAddress--; if (dmxAddress < 1) dmxAddress = 512; }
    } else {
      if (subindo) {
        targetPosMM = min(maxAlturaCaboMM, targetPosMM + 5.0);
      } else {
        targetPosMM = max(0.0, targetPosMM - 5.0);
      }
      targetPosition = (int)(targetPosMM * stepsPerMM);
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
        preferences.begin("mileto_cfg", false);
        preferences.putInt("dmx", dmxAddress);
        preferences.end();
      }
    }
  }
  lastSwState = currentSwState;
}

void gerenciarMovimentoMotor() {
  if (isHoming) {
    // Se estiver fazendo homing, desce o cabo até tocar o sensor home (LOW se acionado)
    if (digitalRead(SENSOR_HOME) == HIGH) {
      gerarPulsoPasso(false); // Direção Descida
    } else {
      currentPosition = 0;
      currentPosMM = 0.0;
      targetPosition = 0;
      targetPosMM = 0.0;
      isHoming = false;
      isCalibrated = true;
    }
  } else {
    // Modo normal: Move em direção à posição alvo (targetPosition)
    if (currentPosition < targetPosition) {
      gerarPulsoPasso(true); // Sobe
    } else if (currentPosition > targetPosition) {
      gerarPulsoPasso(false); // Desce
    }
  }
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
    display.print("DMX CH: "); display.print(dmxAddress);

    display.setCursor(0, 32);
    display.print("ALTURA REAL: "); display.print(currentPosMM, 1); display.print(" mm");

    display.setCursor(0, 48);
    if (faseAtual == FASE_ALTURA) display.print("> "); else display.print("  ");
    display.print("ALTURA ALVO: "); display.print(targetPosMM, 1); display.print(" mm");
    display.display();
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("KINETIC ENGINE INITIALIZING...");

  pinMode(STEP_PIN, OUTPUT);
  pinMode(DIR_PIN, OUTPUT);
  pinMode(EN_PIN, OUTPUT);
  pinMode(SENSOR_HOME, INPUT_PULLUP);

  digitalWrite(EN_PIN, LOW); // Habilita o driver de passo

  Wire.begin(8, 9);
  if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) { Serial.println("OLED ERR"); }

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(15, 20);
  display.print("MOTOR CINETICO");
  display.display();
  delay(1500);

  pinMode(ENC_CLK, INPUT_PULLUP);
  pinMode(ENC_DT, INPUT_PULLUP);
  pinMode(ENC_SW, INPUT_PULLUP);
  lastClkState = digitalRead(ENC_CLK);

  preferences.begin("mileto_cfg", true);
  dmxAddress = preferences.getInt("dmx", 1);
  preferences.end();

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
  pAdvertising->start();

  Serial.println("KINETIC MOTOR ACTIVE!");
}

void loop() {
  if (novoComandoBle) { processarBluetooth(); novoComandoBle = false; comandoPendente = ""; }

  lidarComEncoder();
  gerenciarMovimentoMotor();
  atualizarOLED();
  enviarEstatisticasBT();

  static bool ultimoEstadoConexao = false;
  static unsigned long lastAuthReq = 0;
  if (dispositivoConectado != ultimoEstadoConexao) {
    ultimoEstadoConexao = dispositivoConectado;
    if (dispositivoConectado) { lastAuthReq = millis(); }
  }
  if (dispositivoConectado && !autenticado && millis() - lastAuthReq >= 2000) {
    lastAuthReq = millis();
    String msg = "AUTH_CHALLENGE:"; msg += desafioHandshake; msg += "\n";
    pTxCharacteristic->setValue(msg.c_str()); pTxCharacteristic->notify();
  }
}