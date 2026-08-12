import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'conecta.dart';
import 'mesa_dmx_page.dart';
import 'motor_sinetico_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KINETIC CONTROL',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepOrangeAccent,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepOrangeAccent,
          secondary: Colors.amberAccent
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConectaPage())
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.deepOrangeAccent, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.settings_input_composite_rounded,
                size: 80,
                color: Colors.deepOrangeAccent
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "KINETIC SYSTEM",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 3.0
              )
            ),
            const Text(
              "DMX & WINCH CONTROLLER",
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey,
                letterSpacing: 2.0
              )
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                color: Colors.deepOrangeAccent,
                backgroundColor: Colors.white10
              )
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final BleDevice? deviceAlvo;
  final int abaInicial;
  const HomeScreen({super.key, this.deviceAlvo, this.abaInicial = 0});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _abaAtiva = 0; // 0 = Motor Cinético, 1 = Mesa DMX 8 Canais
  List<double> fadersDMX8 = List.generate(8, (_) => 0.0);

  List<Map<String, dynamic>> cenasSalvas = [];
  bool executandoShow = false;
  int indiceCenaShow = 0;
  Timer? timerShow;
  double tempoTransicaoShow = 2.0;

  BleDevice? _deviceAlvo;
  bool _isConectado = false;
  bool _isCarregando = false;
  bool _isProdutoValido = false;

  final String _serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String _txUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  final String _rxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

  String _buffer = "";
  final Set<String> _macsVistos = {};

  @override
  void initState() {
    super.initState();
    _abaAtiva = widget.abaInicial;
    _configurarEscutaDeDadosBLE();

    if (widget.deviceAlvo != null) {
      _deviceAlvo = widget.deviceAlvo;
      _isConectado = true;
      _isProdutoValido = true;
    } else {
      Future.delayed(const Duration(milliseconds: 500), () {
        _inicializarEConectarBluetooth();
      });
    }
  }

  void _configurarEscutaDeDadosBLE() {
    UniversalBle.onValueChange = (String dId, String cId, Uint8List val, int? timestamp) {
      if (_deviceAlvo != null && dId == _deviceAlvo!.deviceId) {
        _buffer += utf8.decode(val);
        while (_buffer.contains('\n')) {
          int pos = _buffer.indexOf('\n');
          String linha = _buffer.substring(0, pos).trim();
          _buffer = _buffer.substring(pos + 1);
          if (linha.isEmpty) continue;

          print("📝 Rebranded App recebido: $linha");

          if (linha.startsWith("AUTH_CHALLENGE:")) {
            int challenge = int.tryParse(linha.split(":")[1]) ?? 0;
            int response = (challenge * 2) + 7;
            enviarComando("AUTH_RESPONSE", "$response");
          } else if (linha.contains("MILETO_AUTH:VALID")) {
            setState(() => _isProdutoValido = true);
          } else if (linha.contains("GRAVAR:OK")) {
            _mostrarFeedback("💾 Configurações gravadas!");
          }
        }
      }
    };

    UniversalBle.onConnectionChange = (String dId, bool isConnected, String? error) {
      if (_deviceAlvo != null && dId == _deviceAlvo!.deviceId) {
        setState(() {
          _isConectado = isConnected;
          if (!isConnected) {
            _deviceAlvo = null;
            _isProdutoValido = false;
          }
        });
      }
    };
  }

  Future<void> _inicializarEConectarBluetooth() async {
    setState(() { _isCarregando = true; _isProdutoValido = false; _isConectado = false; });
    _macsVistos.clear();

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]?.isGranted != true || statuses[Permission.bluetoothConnect]?.isGranted != true) {
      setState(() { _isCarregando = false; });
      _mostrarFeedback("⚠️ Permissões negadas.");
      return;
    }

    try {
      await UniversalBle.startScan();

      Completer<BleDevice> c = Completer();
      UniversalBle.onScanResult = (device) {
        String name = device.name ?? 'Sem Nome';
        String id = device.deviceId.toUpperCase();
        if (!_macsVistos.contains(id)) { _macsVistos.add(id); }
        if (name.toUpperCase().contains("MILETO") || name.toUpperCase().contains("KINETIC")) {
          _deviceAlvo = device;
          if (!c.isCompleted) c.complete(device);
        }
      };

      _deviceAlvo = await c.future.timeout(const Duration(seconds: 15));
      await UniversalBle.stopScan();

      if (_deviceAlvo != null) {
        await UniversalBle.connect(_deviceAlvo!.deviceId);
        await Future.delayed(const Duration(milliseconds: 800));
        try {
          await UniversalBle.requestMtu(_deviceAlvo!.deviceId, 251);
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
        await UniversalBle.discoverServices(_deviceAlvo!.deviceId);
        await UniversalBle.setNotifiable(_deviceAlvo!.deviceId, _serviceUuid, _txUuid, BleInputProperty.notification);

        setState(() { _isConectado = true; _isCarregando = false; });
      }
    } catch (e) {
      try { await UniversalBle.stopScan(); } catch (_) {}
      setState(() { _isConectado = false; _isCarregando = false; _isProdutoValido = false; _deviceAlvo = null; });
      _mostrarFeedback("Falha na conexão.");
    }
  }

  void enviarComando(String cmd, String val) async {
    if (_isConectado && _deviceAlvo != null) {
      String data = "$cmd:$val\n";
      Uint8List bytes = Uint8List.fromList(utf8.encode(data));
      try {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, _serviceUuid, _rxUuid, bytes, BleOutputProperty.withResponse);
      } catch (_) {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, _serviceUuid, _rxUuid, bytes, BleOutputProperty.withoutResponse);
      }
    }
  }

  void _mostrarFeedback(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _dispararCena(Map<String, dynamic> cena) {
    setState(() {
      if (cena.containsKey('faders')) {
        fadersDMX8 = List<double>.from(cena['faders']);
      }
    });

    if (cena.containsKey('faders')) {
      for (int i = 0; i < 8; i++) {
        enviarComando("SET_CH${i + 1}", "${fadersDMX8[i].round()}");
      }
    }
  }

  void _iniciarShowDeCenas() {
    if (cenasSalvas.isEmpty) {
      _mostrarFeedback("Nenhuma cena salva para iniciar o show.");
      return;
    }
    setState(() {
      executandoShow = true;
      indiceCenaShow = 0;
    });

    _dispararCena(cenasSalvas[indiceCenaShow]);
    _mostrarFeedback("▶️ Show Iniciado! Cena: ${cenasSalvas[indiceCenaShow]['nome']}");

    timerShow?.cancel();
    timerShow = Timer.periodic(Duration(milliseconds: (tempoTransicaoShow * 1000).round()), (timer) {
      if (!mounted || !executandoShow) {
        timer.cancel();
        return;
      }
      setState(() {
        indiceCenaShow = (indiceCenaShow + 1) % cenasSalvas.length;
      });
      _dispararCena(cenasSalvas[indiceCenaShow]);
    });
  }

  void _pararShowDeCenas() {
    timerShow?.cancel();
    setState(() {
      executandoShow = false;
    });
    _mostrarFeedback("⏹️ Show Parado!");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("KINETIC SYSTEM", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrangeAccent)),
        actions: [
          if (_isConectado)
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.amber),
              tooltip: "Re-escanear",
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ConectaPage(activeDevice: _deviceAlvo),
                  ),
                );
              },
            ),
          IconButton(
            icon: Icon(_isConectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _isConectado ? Colors.green : Colors.red),
            onPressed: _inicializarEConectarBluetooth,
          )
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF141414),
      ),
      body: SafeArea(
        child: _isCarregando ? const Center(child: CircularProgressIndicator(color: Colors.deepOrangeAccent))
            : (_isConectado == false) ? const Center(child: Text("DESCONECTADO\n(TOQUE NO ÍCONE SUPERIOR)", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
            : _abaAtiva == 0
                ? KineticMotorPage(deviceAlvo: _deviceAlvo)
                : MesaDmxPage(
                    fadersDMX8: fadersDMX8,
                    cenasSalvas: cenasSalvas,
                    executandoShow: executandoShow,
                    indiceCenaShow: indiceCenaShow,
                    tempoTransicaoShow: tempoTransicaoShow,
                    modosLista: const ["MANUAL", "FADE"],
                    modoAtual: 0,
                    velocidad: 100.0,
                    brilhoGeral: 100.0,
                    brilhoCanaisManuais: const [100, 100, 100, 100],
                    velocidadesCanaisManuais: const [100, 100, 100, 100],
                    enviarComando: enviarComando,
                    mostrarFeedback: _mostrarFeedback,
                    dispararCena: _dispararCena,
                    iniciarShowDeCenas: _iniciarShowDeCenas,
                    pararShowDeCenas: _pararShowDeCenas,
                    setTempoTransicaoShow: (v) => setState(() => tempoTransicaoShow = v),
                    setCenasSalvas: (v) => setState(() => cenasSalvas = v),
                  ),
      ),
      bottomNavigationBar: _isConectado ? BottomNavigationBar(
        currentIndex: _abaAtiva,
        selectedItemColor: Colors.deepOrangeAccent,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF141414),
        onTap: (index) {
          setState(() {
            _abaAtiva = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_input_composite),
            label: "Motor Cinético",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: "Mesa DMX",
          ),
        ],
      ) : null,
    );
  }
}