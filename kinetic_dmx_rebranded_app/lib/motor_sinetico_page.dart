import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

class RebrandedMotor {
  final String uid;
  final String nome;
  int dmxAddress;
  int currentPosition;
  int targetPosition;
  bool isCalibrated;
  bool isHoming;
  double currentPosCM;
  double targetPosCM;
  int stepsDeviation;

  RebrandedMotor({
    required this.uid,
    required this.nome,
    this.dmxAddress = 1,
    this.currentPosition = 0,
    this.targetPosition = 0,
    this.isCalibrated = false,
    this.isHoming = false,
    this.currentPosCM = 0.0,
    this.targetPosCM = 0.0,
    this.stepsDeviation = 0,
  });
}

class KineticMotorPage extends StatefulWidget {
  final BleDevice? deviceAlvo;
  const KineticMotorPage({super.key, this.deviceAlvo});

  @override
  State<KineticMotorPage> createState() => _KineticMotorPageState();
}

class _KineticMotorPageState extends State<KineticMotorPage> {
  static const String serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String txUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  static const String rxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

  BleDevice? _deviceAlvo;
  bool isConnected = false;
  bool isAuthenticated = false;
  String _buffer = "";

  List<RebrandedMotor> motoresConectados = [];
  int motorSelecionadoIdx = 0;

  static const double maxAlturaCaboCM = 300.0; // 300 cm (3 metros) de curso máximo!
  static const double stepsPerMM = 18.0;

  @override
  void initState() {
    super.initState();
    if (widget.deviceAlvo != null) {
      _deviceAlvo = widget.deviceAlvo;
      isConnected = true;
      isAuthenticated = true;
    }
    _configurarEscutaBLEMotores();
    inicializarMotores();
  }

  void inicializarMotores() {
    motoresConectados = [
      RebrandedMotor(
        uid: "4D49:001F2A3B",
        nome: "Guincho Cinético 01",
        dmxAddress: 1,
        currentPosition: 18000,
        targetPosition: 18000,
        currentPosCM: 100.0,
        targetPosCM: 100.0,
        isCalibrated: true,
      ),
      RebrandedMotor(
        uid: "4D49:001F2A3C",
        nome: "Guincho Cinético 02",
        dmxAddress: 8,
        currentPosition: 36000,
        targetPosition: 36000,
        currentPosCM: 200.0,
        targetPosCM: 200.0,
        isCalibrated: true,
      ),
    ];
  }

  void _configurarEscutaBLEMotores() {
    UniversalBle.onValueChange = (String dId, String cId, Uint8List val, int? timestamp) {
      if (_deviceAlvo != null && dId == _deviceAlvo!.deviceId) {
        _buffer += utf8.decode(val);
        while (_buffer.contains('\n')) {
          int pos = _buffer.indexOf('\n');
          String linha = _buffer.substring(0, pos).trim();
          _buffer = _buffer.substring(pos + 1);
          if (linha.isEmpty) continue;

          if (linha.startsWith("AUTH_CHALLENGE:")) {
            int challenge = int.tryParse(linha.split(":")[1]) ?? 0;
            int response = (challenge * 2) + 7;
            sendRawCommand("AUTH_RESPONSE:$response");
          } else if (linha.contains("MILETO_AUTH:VALID")) {
            setState(() {
              isAuthenticated = true;
              motoresConectados.clear();
              motorSelecionadoIdx = 0;
            });
            sendRawCommand("VARREDURA_RDM:0");
          } else if (linha.startsWith("RDM_DEV:")) {
            final payload = linha.split(":")[1].trim();
            final parts = payload.split(",");
            if (parts.length >= 5) {
              final String manId = parts[0];
              final String devId = parts[1];
              final int addr = int.tryParse(parts[2]) ?? 1;
              final String modelName = parts[4];
              final String fullUid = "${manId.toUpperCase()}:${devId.toUpperCase()}";

              setState(() {
                bool existe = motoresConectados.any((m) => m.uid == fullUid);
                if (!existe) {
                  motoresConectados.add(
                    RebrandedMotor(
                      uid: fullUid,
                      nome: "$modelName [$fullUid]",
                      dmxAddress: addr,
                      isCalibrated: false,
                    ),
                  );
                }
              });
            }
          } else if (linha.startsWith("STATS:")) {
            final statsPayload = linha.split(":")[1].trim();
            final parts = statsPayload.split(",");
            if (parts.length >= 10 && motoresConectados.isNotEmpty) {
              setState(() {
                var m = motoresConectados[0];
                m.isCalibrated = parts[0] == "1";
                m.isHoming = parts[1] == "1";
                m.currentPosition = int.tryParse(parts[2]) ?? 0;
                m.targetPosition = int.tryParse(parts[3]) ?? 0;

                // Converte milímetros do ESP32 para centímetros no app dividindo por 10.0
                double realMM = double.tryParse(parts[6]) ?? 0.0;
                double alvoMM = double.tryParse(parts[7]) ?? 0.0;

                m.currentPosCM = (realMM / 10.0).clamp(0.0, maxAlturaCaboCM);
                m.targetPosCM = (alvoMM / 10.0).clamp(0.0, maxAlturaCaboCM);
                m.stepsDeviation = int.tryParse(parts[9]) ?? 0;
              });
            }
          }
        }
      }
    };

    UniversalBle.onConnectionChange = (String dId, bool isConn, String? error) {
      if (_deviceAlvo != null && dId == _deviceAlvo!.deviceId) {
        setState(() {
          isConnected = isConn;
          if (!isConn) {
            _deviceAlvo = null;
            isAuthenticated = false;
          }
        });
      }
    };
  }

  void sendRawCommand(String cmd) async {
    if (isConnected && _deviceAlvo != null) {
      String data = "$cmd\n";
      Uint8List bytes = Uint8List.fromList(utf8.encode(data));
      try {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, serviceUuid, rxUuid, bytes, BleOutputProperty.withResponse);
      } catch (_) {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, serviceUuid, rxUuid, bytes, BleOutputProperty.withoutResponse);
      }
    }
  }

  void setTargetPosition(RebrandedMotor motor, int targetSteps) {
    setState(() {
      motor.targetPosition = targetSteps;
      motor.targetPosCM = ((targetSteps / stepsPerMM) / 10.0).clamp(0.0, maxAlturaCaboCM);
      if (!isConnected) {
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (motor.currentPosition < motor.targetPosition) {
            motor.currentPosition = min(motor.currentPosition + 300, motor.targetPosition);
          } else if (motor.currentPosition > motor.targetPosition) {
            motor.currentPosition = max(motor.currentPosition - 300, motor.targetPosition);
          }
          motor.currentPosCM = (motor.currentPosition / stepsPerMM) / 10.0;
          if (mounted) setState(() {});
          if (motor.currentPosition == motor.targetPosition) {
            timer.cancel();
          }
        });
      }
    });

    if (isConnected) {
      sendRawCommand("SET_POS:$targetSteps");
    }
  }

  void triggerHoming(RebrandedMotor motor) {
    setState(() {
      motor.isHoming = true;
    });
    if (isConnected) {
      sendRawCommand("CALIBRAR:0");
    }
  }

  void stopStepper(RebrandedMotor motor) {
    setState(() {
      motor.targetPosition = motor.currentPosition;
      motor.targetPosCM = motor.currentPosCM;
    });
    if (isConnected) {
      sendRawCommand("PARAR:0");
    }
  }

  Widget _buildTelemetryTile(String label, String value, Color valColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        Text(value, style: TextStyle(color: valColor, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (motoresConectados.isEmpty) {
      motoresConectados.add(RebrandedMotor(
        uid: "4D49:00000001",
        nome: "Guincho Principal",
        dmxAddress: 1,
      ));
    }

    final motorAtivo = motoresConectados[motorSelecionadoIdx < motoresConectados.length ? motorSelecionadoIdx : 0];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Card(
              color: isConnected ? const Color(0xFF1B2D1B) : const Color(0xFF2D1B1B),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: isConnected ? Colors.green : Colors.red,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isConnected ? "Console Pareado | Canal Seguro" : "Modo de Demonstração / Offline",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Card(
              color: const Color(0xFF141414),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "CONTROLE DIRETO: ${motorAtivo.nome}",
                      style: const TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Simulador do Guincho em Centímetros
                        Expanded(
                          flex: 3,
                          child: Container(
                            height: 280,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ClipRect(
                              child: CustomPaint(
                                painter: WinchRebrandedPainter(
                                  alturaAtualCM: motorAtivo.currentPosCM,
                                  alturaAlvoCM: motorAtivo.targetPosCM,
                                  maxCM: maxAlturaCaboCM,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Telemetrias
                        Expanded(
                          flex: 2,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTelemetryTile("Altura Real", "${motorAtivo.currentPosCM.toStringAsFixed(1)} cm", Colors.green),
                              const SizedBox(height: 12),
                              _buildTelemetryTile("Altura Alvo", "${motorAtivo.targetPosCM.toStringAsFixed(1)} cm", Colors.deepOrangeAccent),
                              const SizedBox(height: 12),
                              _buildTelemetryTile("Endereço DMX", "${motorAtivo.dmxAddress}", Colors.cyan),
                              const SizedBox(height: 12),
                              _buildTelemetryTile("Calibrado", motorAtivo.isCalibrated ? "SIM" : "NÃO", motorAtivo.isCalibrated ? Colors.green : Colors.red),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "REGULAR ALTURA DO CABO (0 a 300cm)",
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                    Slider(
                      value: motorAtivo.targetPosCM,
                      min: 0.0,
                      max: maxAlturaCaboCM,
                      divisions: 300,
                      activeColor: Colors.deepOrangeAccent,
                      inactiveColor: Colors.white12,
                      onChanged: (val) {
                        setState(() {
                          motorAtivo.targetPosCM = val;
                          motorAtivo.targetPosition = (val * 10.0 * stepsPerMM).toInt();
                        });
                        setTargetPosition(motorAtivo, motorAtivo.targetPosition);
                      },
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ElevatedButton(
                          onPressed: () => setTargetPosition(motorAtivo, 0),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[850]),
                          child: const Text("Zerar (0cm)", style: TextStyle(fontSize: 10, color: Colors.white)),
                        ),
                        ElevatedButton(
                          onPressed: () => setTargetPosition(motorAtivo, (1500 * stepsPerMM).toInt()),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[850]),
                          child: const Text("Metade (150cm)", style: TextStyle(fontSize: 10, color: Colors.white)),
                        ),
                        ElevatedButton(
                          onPressed: () => setTargetPosition(motorAtivo, (3000 * stepsPerMM).toInt()),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[850]),
                          child: const Text("Máximo (300cm)", style: TextStyle(fontSize: 10, color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => triggerHoming(motorAtivo),
                            icon: const Icon(Icons.refresh, size: 14),
                            label: const Text("Resetar Origem", style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[800]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => stopStepper(motorAtivo),
                            icon: const Icon(Icons.warning_amber_rounded, size: 14),
                            label: const Text("PARAR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text("EQUIPAMENTOS ATIVOS NO BARRAMENTO", style: TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.bold)),
          ),

          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              itemCount: motoresConectados.length,
              itemBuilder: (context, index) {
                final motor = motoresConectados[index];
                final bool sel = motorSelecionadoIdx == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      motorSelecionadoIdx = index;
                    });
                  },
                  child: Card(
                    color: sel ? Colors.deepOrangeAccent.withOpacity(0.1) : const Color(0xFF141414),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: sel ? Colors.deepOrangeAccent : Colors.transparent, width: 1.5),
                    ),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            motor.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text("DMX: ${motor.dmxAddress}", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                          const SizedBox(height: 4),
                          Text("${motor.currentPosCM.toStringAsFixed(0)}cm / ${motor.targetPosCM.toStringAsFixed(0)}cm", style: const TextStyle(color: Colors.deepOrangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class WinchRebrandedPainter extends CustomPainter {
  final double alturaAtualCM;
  final double alturaAlvoCM;
  final double maxCM;

  WinchRebrandedPainter({
    required this.alturaAtualCM,
    required this.alturaAlvoCM,
    required this.maxCM,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;

    // Desenho do Motor Minimalista
    final motorPaint = Paint()..color = const Color(0xFF222222)..style = PaintingStyle.fill;
    final motorOutline = Paint()..color = Colors.deepOrangeAccent.withOpacity(0.5)..strokeWidth = 1.5..style = PaintingStyle.stroke;

    final RRect motorRRect = RRect.fromRectAndRadius(Rect.fromLTWH(center - 35, 10, 70, 50), const Radius.circular(6));
    canvas.drawRRect(motorRRect, motorPaint);
    canvas.drawRRect(motorRRect, motorOutline);

    // Carretel
    final drumPaint = Paint()..color = const Color(0xFF141414)..style = PaintingStyle.fill;
    final drumBorder = Paint()..color = Colors.blueGrey..strokeWidth = 1.5..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(center - 25, 70, 50, 24), drumPaint);
    canvas.drawRect(Rect.fromLTWH(center - 25, 70, 50, 24), drumBorder);

    // Cabos e Alturas
    final cablePaint = Paint()..color = const Color(0xFFE0E0E0)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final targetCablePaint = Paint()..color = Colors.deepOrangeAccent.withOpacity(0.2)..strokeWidth = 1.0..style = PaintingStyle.stroke;

    final double pontoInicioY = 94.0;
    final double areaUtilY = size.height - pontoInicioY - 50.0;

    final double pixelsAtual = (alturaAtualCM / maxCM) * areaUtilY;
    final double pixelsAlvo = (alturaAlvoCM / maxCM) * areaUtilY;

    final double fimYAtual = pontoInicioY + pixelsAtual;
    final double fimYAlvo = pontoInicioY + pixelsAlvo;

    canvas.drawLine(Offset(center, pontoInicioY), Offset(center, fimYAlvo), targetCablePaint);
    canvas.drawLine(Offset(center, pontoInicioY), Offset(center, fimYAtual), cablePaint);

    // Cúpula do Guincho (Luz de Destaque)
    final Paint glowPaint = Paint()..color = Colors.deepOrangeAccent.withOpacity(0.3)..style = PaintingStyle.fill;
    final Paint corePaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center, fimYAtual), 15, glowPaint);
    canvas.drawCircle(Offset(center, fimYAtual), 6, corePaint);

    // Cabine/Estrutura Minimalista Suspensa
    final Paint boxPaint = Paint()..color = const Color(0xFF333333)..style = PaintingStyle.fill;
    final Paint boxOutline = Paint()..color = Colors.deepOrangeAccent..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final Rect boxRect = Rect.fromLTWH(center - 20, fimYAtual, 40, 30);
    canvas.drawRect(boxRect, boxPaint);
    canvas.drawRect(boxRect, boxOutline);

    // Cruz interna metálica
    final crossPaint = Paint()..color = Colors.deepOrangeAccent.withOpacity(0.3)..strokeWidth = 1.0;
    canvas.drawLine(Offset(center - 20, fimYAtual), Offset(center + 20, fimYAtual + 30), crossPaint);
    canvas.drawLine(Offset(center + 20, fimYAtual), Offset(center - 20, fimYAtual + 30), crossPaint);

    // Régua Métrica Lateral
    final textPaint = Paint()..color = Colors.white24..strokeWidth = 1;
    const int divisions = 3;
    for (int i = 0; i <= divisions; i++) {
      double pct = i / divisions;
      double y = pontoInicioY + (pct * areaUtilY);
      double valorCM = pct * maxCM;

      canvas.drawLine(Offset(center - 35, y), Offset(center - 28, y), textPaint);

      final textSpan = TextSpan(
        text: "${valorCM.toStringAsFixed(0)} cm",
        style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(center - 75, y - 5));
    }
  }

  @override
  bool shouldRepaint(covariant WinchRebrandedPainter oldDelegate) {
    return oldDelegate.alturaAtualCM != alturaAtualCM || oldDelegate.alturaAlvoCM != alturaAlvoCM || oldDelegate.maxCM != maxCM;
  }
}