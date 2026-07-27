import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'conecta.dart';

// Classe modelo para representar cada Motor Cinético de forma individual
class MotorCinetico {
  final String uid;
  final String nome;
  int dmxAddress;
  int currentPosition;
  int targetPosition;
  bool isCalibrated;
  bool isHoming;
  double currentPosMM;
  double targetPosMM;
  int stepsDeviation;

  MotorCinetico({
    required this.uid,
    required this.nome,
    this.dmxAddress = 1,
    this.currentPosition = 0,
    this.targetPosition = 0,
    this.isCalibrated = false,
    this.isHoming = false,
    this.currentPosMM = 0.0,
    this.targetPosMM = 0.0,
    this.stepsDeviation = 0,
  });
}

class MiletoControlPage extends StatefulWidget {
  final BleDevice? deviceAlvo;
  const MiletoControlPage({super.key, this.deviceAlvo});

  @override
  State<MiletoControlPage> createState() => _MiletoControlPageState();
}

class _MiletoControlPageState extends State<MiletoControlPage> {
  static const String serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String txUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  static const String rxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

  BleDevice? _deviceAlvo;
  bool isConnected = false;
  bool isAuthenticated = false;
  String _buffer = "";

  // Lista de Motores Cinéticos Conectados / Detectados Individualmente
  List<MotorCinetico> motoresConectados = [];

  // Constantes de cálculo baseadas em cabo de 400mm útil máximo
  static const double maxAlturaCaboMM = 400.0;
  static const double stepsPerMM = 40.0; // Exemplo: 16000 passos para 400mm de curso

  @override
  void initState() {
    super.initState();
    if (widget.deviceAlvo != null) {
      _deviceAlvo = widget.deviceAlvo;
      isConnected = true;
      isAuthenticated = true;
    }
    _configurarEscutaBLEMotores();
    inicializarMotoresSimulados();
  }

  void inicializarMotoresSimulados() {
    // Inicializa com motores simulados para demonstração offline e facilidade de testes individuais
    motoresConectados = [
      MotorCinetico(
        uid: "4D49:001F2A3B",
        nome: "Motor Cinético Paris 01",
        dmxAddress: 1,
        currentPosition: 4000,
        targetPosition: 4000,
        currentPosMM: 100.0,
        targetPosMM: 100.0,
        isCalibrated: true,
      ),
      MotorCinetico(
        uid: "4D49:001F2A3C",
        nome: "Motor Cinético Paris 02",
        dmxAddress: 8,
        currentPosition: 12000,
        targetPosition: 12000,
        currentPosMM: 300.0,
        targetPosMM: 300.0,
        isCalibrated: true,
      ),
      MotorCinetico(
        uid: "4D49:001F2A3D",
        nome: "Motor Cinético Paris 03",
        dmxAddress: 15,
        currentPosition: 0,
        targetPosition: 8000,
        currentPosMM: 0.0,
        targetPosMM: 200.0,
        isCalibrated: false,
      ),
      MotorCinetico(
        uid: "4D49:001F2A3E",
        nome: "Motor Cinético Paris 04",
        dmxAddress: 22,
        currentPosition: 16000,
        targetPosition: 16000,
        currentPosMM: 400.0,
        targetPosMM: 400.0,
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

          print("📝 Motores recebido: $linha");

          if (linha.startsWith("AUTH_CHALLENGE:")) {
            int challenge = int.tryParse(linha.split(":")[1]) ?? 0;
            int response = (challenge * 2) + 7;
            sendRawCommand("AUTH_RESPONSE:$response");
          } else if (linha.contains("MILETO_AUTH:VALID")) {
            setState(() {
              isAuthenticated = true;
              motoresConectados.clear();
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
                    MotorCinetico(
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
                m.currentPosMM = (double.tryParse(parts[6]) ?? 0.0).clamp(0.0, maxAlturaCaboMM);
                m.targetPosMM = (double.tryParse(parts[7]) ?? 0.0).clamp(0.0, maxAlturaCaboMM);
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

  void setTargetPosition(MotorCinetico motor, int targetSteps) {
    setState(() {
      motor.targetPosition = targetSteps;
      motor.targetPosMM = (targetSteps / stepsPerMM).clamp(0.0, maxAlturaCaboMM);
      if (!isConnected) {
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (motor.currentPosition < motor.targetPosition) {
            motor.currentPosition = min(motor.currentPosition + 300, motor.targetPosition);
          } else if (motor.currentPosition > motor.targetPosition) {
            motor.currentPosition = max(motor.currentPosition - 300, motor.targetPosition);
          }
          motor.currentPosMM = motor.currentPosition / stepsPerMM;
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

  void triggerHoming(MotorCinetico motor) {
    setState(() {
      motor.isHoming = true;
      if (!isConnected) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              motor.isHoming = false;
              motor.isCalibrated = true;
              motor.currentPosition = 0;
              motor.currentPosMM = 0.0;
              motor.targetPosition = 0;
              motor.targetPosMM = 0.0;
            });
          }
        });
      }
    });

    if (isConnected) {
      sendRawCommand("CALIBRAR:0");
    }
  }

  void stopStepper(MotorCinetico motor) {
    setState(() {
      motor.targetPosition = motor.currentPosition;
      motor.targetPosMM = motor.currentPosMM;
    });
    if (isConnected) {
      sendRawCommand("PARAR:0");
    }
  }

  void saveConfig() {
    if (isConnected) {
      sendRawCommand("GRAVAR:0");
    }
  }

  void abrirProgramacaoIndividual(MotorCinetico motor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF151515),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            motor.nome,
                            style: const TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "UID RDM: ${motor.uid} | Canal DMX: ${motor.dmxAddress}",
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 20),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ClipRect(
                              child: CustomPaint(
                                painter: WinchKineticPainter(
                                  alturaAtualMM: motor.currentPosMM,
                                  alturaAlvoMM: motor.targetPosMM,
                                  maxMM: maxAlturaCaboMM,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTelemetryTile("Altura Real", "${motor.currentPosMM.toStringAsFixed(1)} mm", Colors.green),
                              const SizedBox(height: 12),
                              _buildTelemetryTile("Altura Alvo", "${motor.targetPosMM.toStringAsFixed(1)} mm", Colors.amber),
                              const SizedBox(height: 12),
                              _buildTelemetryTile("Passos Motor", "${motor.currentPosition}", Colors.white),
                              const SizedBox(height: 12),
                              _buildTelemetryTile("Calibrado", motor.isCalibrated ? "SIM" : "NÃO", motor.isCalibrated ? Colors.green : Colors.red),
                              if (motor.isHoming) ...[
                                const SizedBox(height: 12),
                                const Row(
                                  children: [
                                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
                                    SizedBox(width: 8),
                                    Text("Buscando Zero...", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Programar Altura do Cabo (0 a 400mm)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
                  Slider(
                    value: motor.targetPosMM,
                    min: 0.0,
                    max: maxAlturaCaboMM,
                    divisions: 400,
                    activeColor: Colors.amber[700],
                    inactiveColor: Colors.white12,
                    label: "${motor.targetPosMM.toStringAsFixed(0)} mm",
                    onChanged: (val) {
                      setModalState(() {
                        motor.targetPosMM = val;
                        motor.targetPosition = (val * stepsPerMM).toInt();
                      });
                      setState(() {});
                      setTargetPosition(motor, motor.targetPosition);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          setModalState(() {
                            motor.targetPosMM = 0.0;
                            motor.targetPosition = 0;
                          });
                          setState(() {});
                          setTargetPosition(motor, 0);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                        child: const Text("Zerar Cabo"),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setModalState(() {
                            motor.targetPosMM = maxAlturaCaboMM / 2;
                            motor.targetPosition = (motor.targetPosMM * stepsPerMM).toInt();
                          });
                          setState(() {});
                          setTargetPosition(motor, motor.targetPosition);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                        child: const Text("Metade (200mm)"),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setModalState(() {
                            motor.targetPosMM = maxAlturaCaboMM;
                            motor.targetPosition = (maxAlturaCaboMM * stepsPerMM).toInt();
                          });
                          setState(() {});
                          setTargetPosition(motor, motor.targetPosition);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                        child: const Text("Curso Máx (400mm)"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          triggerHoming(motor);
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text("Zerar Motor"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          stopStepper(motor);
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.stop, size: 16),
                        label: const Text("PARADA DE EMERGÊNCIA"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTelemetryTile(String label, String value, Color valColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        Text(value, style: TextStyle(color: valColor, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Motores Cinéticos Mileto', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ConectaPage()),
            );
          },
        ),
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.save, color: Colors.amber),
              tooltip: "Gravar Todas as Configurações na NVS",
              onPressed: saveConfig,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              color: isConnected ? const Color(0xFF1B2D1B) : const Color(0xFF2D1B1B),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: isConnected ? Colors.green : Colors.red,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected ? "Controlador Mileto Pareado" : "Controlador Offline (Simulador)",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            isConnected
                                ? (isAuthenticated ? "Autenticado & Seguro" : "Aguardando Autenticação...")
                                : "Modo de Teste Manual Individual Habilitado",
                            style: TextStyle(color: isConnected ? Colors.white70 : Colors.amber, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              "Motores Cinéticos Conectados (Clique para programar)",
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemCount: motoresConectados.length,
              itemBuilder: (context, index) {
                final motor = motoresConectados[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.settings_input_composite, color: Colors.amber),
                    ),
                    title: Text(motor.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("DMX: ${motor.dmxAddress} | UID: ${motor.uid}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: motor.isCalibrated ? Colors.green[800] : Colors.red[800],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                motor.isCalibrated ? "Calibrado" : "Não Calibrado",
                                style: const TextStyle(color: Colors.white, fontSize: 9),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text("Posição: ${motor.currentPosMM.toStringAsFixed(1)} mm", style: const TextStyle(color: Colors.amber, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                    onTap: () => abrirProgramacaoIndividual(motor),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WinchKineticPainter extends CustomPainter {
  final double alturaAtualMM;
  final double alturaAlvoMM;
  final double maxMM;

  WinchKineticPainter({
    required this.alturaAtualMM,
    required this.alturaAlvoMM,
    required this.maxMM,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final motorPaint = Paint()..color = Colors.grey[850]!..style = PaintingStyle.fill;
    final motorOutline = Paint()..color = Colors.white24..strokeWidth = 2..style = PaintingStyle.stroke;
    final motorRect = Rect.fromLTWH(center - 35, 15, 70, 50);
    canvas.drawRect(motorRect, motorPaint);
    canvas.drawRect(motorRect, motorOutline);

    final linePaint = Paint()..color = Colors.black..strokeWidth = 3;
    for (int i = 0; i < 5; i++) {
      double y = 20.0 + (i * 9);
      canvas.drawLine(Offset(center - 30, y), Offset(center + 30, y), linePaint);
    }

    final drumPaint = Paint()..color = Colors.blueGrey[800]!..style = PaintingStyle.fill;
    final drumInnerPaint = Paint()..color = Colors.blueGrey[900]!..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(center, 90), 30, drumPaint);
    canvas.drawCircle(Offset(center, 90), 24, drumInnerPaint);
    canvas.drawCircle(Offset(center, 90), 10, motorPaint);

    final cablePaint = Paint()..color = Colors.amber[300]!..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final targetCablePaint = Paint()..color = Colors.amber.withOpacity(0.3)..strokeWidth = 1.5..style = PaintingStyle.stroke;

    final double pontoInicioCaboY = 90.0;
    final double pontoInicioCaboX = center + 24;
    final double areaUtilPixelsY = size.height - pontoInicioCaboY - 60.0;

    final double pixelsAlturaAtual = (alturaAtualMM / maxMM) * areaUtilPixelsY;
    final double pixelsAlturaAlvo = (alturaAlvoMM / maxMM) * areaUtilPixelsY;

    final double pontoFimCaboY_Atual = pontoInicioCaboY + pixelsAlturaAtual;
    final double pontoFimCaboY_Alvo = pontoInicioCaboY + pixelsAlturaAlvo;

    canvas.drawLine(Offset(pontoInicioCaboX, pontoInicioCaboY), Offset(pontoInicioCaboX, pontoFimCaboY_Alvo), targetCablePaint);

    final sphereTargetPaint = Paint()..color = Colors.amber.withOpacity(0.2)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(pontoInicioCaboX, pontoFimCaboY_Alvo), 10, sphereTargetPaint);

    canvas.drawLine(Offset(pontoInicioCaboX, pontoInicioCaboY), Offset(pontoInicioCaboX, pontoFimCaboY_Atual), cablePaint);

    final spherePaint = Paint()..color = Colors.amber[700]!..style = PaintingStyle.fill;
    final sphereHighlight = Paint()..color = Colors.white38..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(pontoInicioCaboX, pontoFimCaboY_Atual), 11, spherePaint);
    canvas.drawCircle(Offset(pontoInicioCaboX - 3, pontoFimCaboY_Atual - 3), 4, sphereHighlight);

    final textPaint = Paint()..color = Colors.white24..strokeWidth = 1;
    const int numDivisions = 4;
    for (int i = 0; i <= numDivisions; i++) {
      double pct = i / numDivisions;
      double y = pontoInicioCaboY + (pct * areaUtilPixelsY);
      double valorMM = pct * maxMM;

      canvas.drawLine(Offset(pontoInicioCaboX - 60, y), Offset(pontoInicioCaboX - 45, y), textPaint);

      final textSpan = TextSpan(text: "${valorMM.toStringAsFixed(0)}mm", style: const TextStyle(color: Colors.white24, fontSize: 9));
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(pontoInicioCaboX - 100, y - 6));
    }
  }

  @override
  bool shouldRepaint(covariant WinchKineticPainter oldDelegate) {
    return oldDelegate.alturaAtualMM != alturaAtualMM || oldDelegate.alturaAlvoMM != alturaAlvoMM || oldDelegate.maxMM != maxMM;
  }
}