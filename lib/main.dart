import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'conecta.dart';
import 'pista_paris_page.dart';
import 'pista_croma_page.dart';
import 'mesa_dmx_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Controle MILETO',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(primary: Colors.amber, secondary: Colors.amberAccent),
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
    Timer(const Duration(seconds: 3), () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ConectaPage())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/mileto_logo.png', width: 180, height: 180, errorBuilder: (c, e, s) => const Text("MILETO", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 4.0))),
            const SizedBox(height: 24),
            const SizedBox(width: 120, child: LinearProgressIndicator(color: Colors.amber, backgroundColor: Colors.white10)),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final BleDevice? deviceAlvo;
  const HomeScreen({super.key, this.deviceAlvo});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _abaAtiva = 0; // 0 = Pista Paris, 1 = Mesa DMX 8 Canais, 2 = Pista Croma RGB
  List<double> fadersDMX8 = List.generate(8, (_) => 0.0);

  // Lista de Cenas Salvas na memória local (Cenas personalizadas)
  List<Map<String, dynamic>> cenasSalvas = [];
  bool executandoShow = false;
  int indiceCenaShow = 0;
  Timer? timerShow;
  double tempoTransicaoShow = 2.0; // segundos

  Future<void> _abrirLink(String urlStr) async {
    final Uri url = Uri.parse(urlStr);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _mostrarFeedback("Não foi possível abrir o link: $urlStr");
    }
  }

  int modoAtual = 0;
  double velocidad = 100;
  double brilhoGeral = 100;
  int enderecoDMX = 1;
  bool modoDMX = false;
  int tamanhoGrade = 4;

  BleDevice? _deviceAlvo;
  bool _isConectado = false;
  bool _isCarregando = false;
  bool _isProdutoMileto = false;

  final String _serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String _txUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  final String _rxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

  List<String> modosLista = ["DMX", "MANUAL", "FADE", "STROBO", "SEQUENC", "FIXO", "XADREZ"];
  String _buffer = "";
  List<double> niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];
  int canalManualSelecionado = 1;
  List<double> brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];
  List<double> velocidadesCanaisManuais = [100.0, 100.0, 100.0, 100.0];

  final Set<String> _macsVistos = {};

  @override
  void initState() {
    super.initState();
    _configurarEscutaDeDadosBLE();

    if (widget.deviceAlvo != null) {
      _deviceAlvo = widget.deviceAlvo;
      _isConectado = true;
      _isProdutoMileto = true;
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

          print("📝 Linha recebida: $linha");

          if (linha.startsWith("AUTH_CHALLENGE:")) {
            int challenge = int.tryParse(linha.split(":")[1]) ?? 0;
            int response = (challenge * 2) + 7;
            enviarComando("AUTH_RESPONSE", "$response");
          } else if (linha.contains("MILETO_AUTH:VALID")) {
            setState(() => _isProdutoMileto = true);
            enviarComando("GET_CAPABILITIES", "1");
          } else if (linha.startsWith("CH_LEVELS:")) {
            List<String> n = linha.replaceAll("CH_LEVELS:", "").split(",");
            if (n.length >= 4) {
              setState(() => niveisReaisCanais = List.generate(4, (i) => double.tryParse(n[i]) ?? 0.0));
            }
          } else if (linha.startsWith("CAPS:")) {
            setState(() => modosLista = linha.replaceAll("CAPS:", "").split(","));
          } else if (linha.startsWith("DMX:")) {
            int? d = int.tryParse(linha.replaceAll("DMX:", ""));
            if (d != null) setState(() => enderecoDMX = d);
          } else if (linha.startsWith("MODO:")) {
            // Sincroniza hardware -> app: "MODO:x|DMX:y"
            List<String> partes = linha.split("|");
            int? m = int.tryParse(partes[0].replaceAll("MODO:", ""));
            if (m != null) setState(() { modoAtual = m; modoDMX = (m == 0); });
            if (partes.length > 1) {
              int? d = int.tryParse(partes[1].replaceAll("DMX:", ""));
              if (d != null) setState(() => enderecoDMX = d);
            }
          } else if (linha.startsWith("CHAVE_MODO:")) {
            setState(() { modoDMX = (linha.replaceAll("CHAVE_MODO:", "") == "DMX"); modoAtual = modoDMX ? 0 : 1; });
          } else if (linha.contains("GRAVAR:OK")) {
            _mostrarFeedback("💾 Configurações salvas!");
          }
        }
      }
    };

    UniversalBle.onConnectionChange = (String dId, bool isConnected, String? error) {
      print("🔌 Conexão $dId: $isConnected. Erro=$error");
      if (_deviceAlvo != null && dId == _deviceAlvo!.deviceId) {
        setState(() {
          _isConectado = isConnected;
          if (!isConnected) {
            _deviceAlvo = null;
            _isProdutoMileto = false;
          }
        });
      }
    };
  }

  Future<void> _inicializarEConectarBluetooth() async {
    if (_isConectado && _deviceAlvo != null) {
      try { await UniversalBle.disconnect(_deviceAlvo!.deviceId); } catch (e) {}
      setState(() { _isConectado = false; _isProdutoMileto = false; _isCarregando = false; });
      return;
    }

    setState(() { _isCarregando = true; _isProdutoMileto = false; _isConectado = false; });
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
      print("Iniciando escaneamento...");
      await UniversalBle.startScan();

      Completer<BleDevice> c = Completer();
      UniversalBle.onScanResult = (device) {
        String name = device.name ?? 'Sem Nome';
        String id = device.deviceId.toUpperCase();
        if (!_macsVistos.contains(id)) { _macsVistos.add(id); print("Detectado: $name | $id"); }
        if (name.toUpperCase().contains("MILETO")) {
          print("🎯 MILETO ENCONTRADO!");
          _deviceAlvo = device;
          if (!c.isCompleted) c.complete(device);
        }
      };

      _deviceAlvo = await c.future.timeout(const Duration(seconds: 15));
      await UniversalBle.stopScan();

      await Future.delayed(const Duration(milliseconds: 800));

      if (_deviceAlvo != null) {
        int tent = 0;
        bool ok = false;
        while (tent < 3 && !ok) {
          tent++;
          try {
            print("⚡ Tentativa $tent/3 conectando...");
            await UniversalBle.connect(_deviceAlvo!.deviceId);
            ok = true;
          } catch (e) {
            if (tent >= 3) rethrow;
            await Future.delayed(const Duration(milliseconds: 1500));
          }
        }

        await Future.delayed(const Duration(milliseconds: 800));
        try {
          await UniversalBle.requestMtu(_deviceAlvo!.deviceId, 251);
          print("MTU configurado com sucesso para 251 bytes!");
        } catch (e) {
          print("Erro ao solicitar MTU: $e");
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await UniversalBle.discoverServices(_deviceAlvo!.deviceId);
        await UniversalBle.setNotifiable(_deviceAlvo!.deviceId, _serviceUuid, _txUuid, BleInputProperty.notification);

        setState(() { _isConectado = true; _isCarregando = false; });
        print("🚀 Conectado!");
      }
    } catch (e) {
      try { await UniversalBle.stopScan(); } catch (_) {}
      setState(() { _isConectado = false; _isCarregando = false; _isProdutoMileto = false; _deviceAlvo = null; });
      _mostrarFeedback("Falha na conexão.");
    }
  }

  void enviarComando(String cmd, String val) async {
    if (_isConectado && _deviceAlvo != null) {
      // Atendimento a comandos de incremento/decremento manuais
      if (cmd == "DECREMENT_DMX") {
        if (enderecoDMX > 1) {
          setState(() => enderecoDMX--);
          enviarComando("SET_DMX", "$enderecoDMX");
        }
        return;
      }
      if (cmd == "INCREMENT_DMX") {
        if (enderecoDMX < 512) {
          setState(() => enderecoDMX++);
          enviarComando("SET_DMX", "$enderecoDMX");
        }
        return;
      }

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

  // Executa uma cena gravada enviando os parâmetros via BLE
  void _dispararCena(Map<String, dynamic> cena) {
    setState(() {
      modoAtual = cena['modo'];
      modoDMX = (modoAtual == 0);
      velocidad = cena['vel'];
      brilhoGeral = cena['dim'];
      brilhoCanaisManuais = List<double>.from(cena['brilhos']);
      velocidadesCanaisManuais = List<double>.from(cena['velocidades']);

      // Se a cena contiver faders DMX salvos, restaura-os
      if (cena.containsKey('faders')) {
        fadersDMX8 = List<double>.from(cena['faders']);
      }
    });

    enviarComando("SET_MODO", "$modoAtual");
    enviarComando("SET_VEL", "${velocidad.round()}");
    enviarComando("SET_DIM", "${brilhoGeral.round()}");

    // Dispara canais individuais
    for (int i = 0; i < 4; i++) {
      enviarComando("SET_CH${i + 1}", "${brilhoCanaisManuais[i].round()}");
      enviarComando("SET_VCH${i + 1}", "${velocidadesCanaisManuais[i].round()}");
    }

    // Dispara faders DMX8 salvos
    if (cena.containsKey('faders')) {
      for (int i = 0; i < 8; i++) {
        enviarComando("SET_CH${i + 1}", "${fadersDMX8[i].round()}");
      }
    }
  }

  // Loop de reprodução automática do Show de Cenas
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
    _mostrarFeedback("▶️ Show Iniciado! Cena 1: ${cenasSalvas[indiceCenaShow]['nome']}");

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
      _mostrarFeedback("Cena ${indiceCenaShow + 1}: ${cenasSalvas[indiceCenaShow]['nome']}");
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
        title: const Text("MILETO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
        actions: [
          if (_isConectado)
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.amberAccent),
              tooltip: "Re-escanear Barramento RDM",
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ConectaPage(activeDevice: _deviceAlvo),
                  ),
                );
              },
            ),
          if (_isCarregando) const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else IconButton(icon: Icon(_isConectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _isConectado ? Colors.greenAccent : Colors.redAccent), onPressed: _inicializarEConectarBluetooth)
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF121212),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                border: Border(bottom: BorderSide(color: Colors.amber, width: 2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/mileto_logo.png',
                    height: 50,
                    errorBuilder: (c, e, s) => const Text(
                      "MILETO",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "CONEXÕES E SITE OFICIAL",
                    style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home, color: Colors.amber),
              title: const Text("HOME WEBSITE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _abrirLink("https://mileto.ind.br/");
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.amber),
              title: const Text("SOBRE NÓS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _abrirLink("https://mileto.ind.br/sobre-nos/");
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.amber),
              title: const Text("PRODUTOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _abrirLink("https://mileto.ind.br/catalogo/");
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: Colors.amber),
              title: const Text("FALE CONOSCO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _abrirLink("https://mileto.ind.br/fale-conosco/");
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.grey),
              title: const Text("CONECTAR DISPOSITIVO", style: TextStyle(color: Colors.grey, fontSize: 13)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ConectaPage()),
                );
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _isCarregando ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.amber), SizedBox(height: 16), Text("Conectando...", style: TextStyle(color: Colors.grey))]))
            : (_isConectado == false) ? const Center(child: Text("DESCONECTADO\n(TOQUE NO ÍCONE ACIMA)", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
            : !_isProdutoMileto ? _buildTelaProdutoNaoEncontrado()
            : _abaAtiva == 0 ? PistaParisPage(
                modoAtual: modoAtual,
                velocidad: velocidad,
                brilhoGeral: brilhoGeral,
                modoDMX: modoDMX,
                tamanhoGrade: tamanhoGrade,
                modosLista: modosLista,
                niveisReaisCanais: niveisReaisCanais,
                canalManualSelecionado: canalManualSelecionado,
                brilhoCanaisManuais: brilhoCanaisManuais,
                velocidadesCanaisManuais: velocidadesCanaisManuais,
                enviarComando: enviarComando,
                setTamanhoGrade: (v) => setState(() => tamanhoGrade = v),
                setCanalManualSelecionado: (v) => setState(() => canalManualSelecionado = v),
                setModoDMX: (v) => setState(() => modoDMX = v),
                setModoAtual: (v) => setState(() => modoAtual = v),
                setVelocidad: (v) => setState(() => velocidad = v),
                setBrilhoGeral: (v) => setState(() => brilhoGeral = v),
              )
            : _abaAtiva == 1 ? MesaDmxPage(
                fadersDMX8: fadersDMX8,
                cenasSalvas: cenasSalvas,
                executandoShow: executandoShow,
                indiceCenaShow: indiceCenaShow,
                tempoTransicaoShow: tempoTransicaoShow,
                modosLista: modosLista,
                modoAtual: modoAtual,
                velocidad: velocidad,
                brilhoGeral: brilhoGeral,
                brilhoCanaisManuais: brilhoCanaisManuais,
                velocidadesCanaisManuais: velocidadesCanaisManuais,
                enviarComando: enviarComando,
                mostrarFeedback: _mostrarFeedback,
                dispararCena: _dispararCena,
                iniciarShowDeCenas: _iniciarShowDeCenas,
                pararShowDeCenas: _pararShowDeCenas,
                setTempoTransicaoShow: (v) => setState(() => tempoTransicaoShow = v),
                setCenasSalvas: (v) => setState(() => cenasSalvas = v),
              )
            : PistaCromaPage(enviarComando: enviarComando),
      ),
      bottomNavigationBar: _isConectado && _isProdutoMileto ? BottomNavigationBar(
        currentIndex: _abaAtiva,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
        onTap: (index) {
          setState(() {
            _abaAtiva = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: "Pista Paris",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: "Mesa 8 CHs",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.palette),
            label: "Pista Croma",
          ),
        ],
      ) : null,
    );
  }

  Widget _buildTelaProdutoNaoEncontrado() {
    return Center(child: Padding(padding: const EdgeInsets.all(32.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.security, size: 80, color: Colors.orangeAccent), const SizedBox(height: 24), const Text("Aguardando validação...", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 32), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)), onPressed: () => _abrirLink("https://mileto.ind.br/"), child: const Text("SITE MILETO"))])));
  }
}