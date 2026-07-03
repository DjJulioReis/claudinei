import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

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
    Timer(const Duration(seconds: 3), () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen())));
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
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  List<String> modosLista = ["DMX", "MANUAL", "FADE", "STROBO", "SEQUENC", "FIXO"];
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
    Future.delayed(const Duration(milliseconds: 500), () {
      _inicializarEConectarBluetooth();
    });
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
          } else if (linha.startsWith("MODO:")) {
            // Sincroniza hardware -> app: "MODO:x|DMX:y"
            List<String> partes = linha.split("|");
            int? m = int.tryParse(partes[0].replaceAll("MODO:", ""));
            if (m != null) setState(() { modoAtual = m; modoDMX = (m == 0); });
            if (partes.length > 1) {
               int? d = int.tryParse(partes[1].replaceAll("DMX:", ""));
               if (d != null) setState(() => enderecoDMX = d);
            }
          } else if (linha.startsWith("CAPS:")) {
            setState(() => modosLista = linha.replaceAll("CAPS:", "").split(","));
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

  Future<void> _abrirSiteMileto() async {
    final Uri url = Uri.parse('https://mileto.ind.br/');
    if (!await launchUrl(url)) _mostrarFeedback("Não foi possível abrir o site.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MILETO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
        actions: [
          if (_isCarregando) const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else IconButton(icon: Icon(_isConectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _isConectado ? Colors.greenAccent : Colors.redAccent), onPressed: _inicializarEConectarBluetooth)
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: SafeArea(
        child: _isCarregando ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.amber), SizedBox(height: 16), Text("Conectando...", style: TextStyle(color: Colors.grey))]))
            : (_isConectado == false) ? const Center(child: Text("DESCONECTADO\n(TOQUE NO ÍCONE ACIMA)", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
            : !_isProdutoMileto ? _buildTelaProdutoNaoEncontrado()
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: const Color(0xFF1E1E1E),
                child: ListTile(
                  title: Text(modoDMX ? "MODO DMX ATIVO" : "MODO MANUAL / RF", style: TextStyle(fontWeight: FontWeight.bold, color: modoDMX ? Colors.cyan : Colors.amber)),
                  trailing: Switch(value: modoDMX, activeColor: Colors.cyan, onChanged: (v) { setState(() { modoDMX = v; modoAtual = v ? 0 : 1; }); enviarComando("CHAVE_MODO", modoDMX ? "DMX" : "RF"); }),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: modoDMX ? _buildPainelDMX() : _buildPainelManuais()),
              const SizedBox(height: 16),
              ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.save), label: const Text("GRAVAR NA MEMÓRIA"), onPressed: () => enviarComando("GRAVAR", "1")),
              const SizedBox(height: 24),
              _buildSimuladorPistaLed(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelaProdutoNaoEncontrado() {
    return Center(child: Padding(padding: const EdgeInsets.all(32.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.security, size: 80, color: Colors.orangeAccent), const SizedBox(height: 24), const Text("Hardware não validado.", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 32), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)), onPressed: _abrirSiteMileto, child: const Text("SITE MILETO"))])));
  }

  Widget _buildPainelDMX() {
    return Card(color: const Color(0xFF1E1E1E), child: Padding(padding: const EdgeInsets.all(20.0), child: Column(children: [const Text("ENDEREÇO DMX", style: TextStyle(color: Colors.grey)), Text("$enderecoDMX", style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.cyan)), const Text("(Ajuste via Encoder)", style: TextStyle(color: Colors.white24, fontSize: 11))])));
  }

  Widget _buildPainelManuais() {
    bool isManual = modoAtual == 1;
    return Column(
      children: [
        Card(
          color: const Color(0xFF1E1E1E),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: modosLista.length - 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.2),
              itemBuilder: (context, index) {
                final int idxModo = index + 1;
                final bool sel = modoAtual == idxModo;
                return ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E), foregroundColor: sel ? Colors.black : Colors.white, padding: EdgeInsets.zero), onPressed: () { setState(() => modoAtual = idxModo); enviarComando("SET_MODO", "$modoAtual"); }, child: Text(modosLista[idxModo], style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        if (isManual) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(4, (index) {
                    final int canal = index + 1;
                    final bool sel = canalManualSelecionado == canal;
                    return Expanded(child: Padding(padding: EdgeInsets.only(right: index < 3 ? 8 : 0), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E), foregroundColor: sel ? Colors.black : Colors.white70, padding: EdgeInsets.zero), onPressed: () => setState(() => canalManualSelecionado = canal), child: Text("CH$canal"))));
                  })),
                  const Divider(height: 32, color: Colors.white10),
                  _buildSliderRow("BRILHO CH$canalManualSelecionado", brilhoCanaisManuais[canalManualSelecionado - 1], (val) => setState(() => brilhoCanaisManuais[canalManualSelecionado - 1] = val), "SET_CH$canalManualSelecionado"),
                  const SizedBox(height: 12),
                  _buildSliderRow("VELOCIDADE CH$canalManualSelecionado", velocidadesCanaisManuais[canalManualSelecionado - 1], (val) => setState(() => velocidadesCanaisManuais[canalManualSelecionado - 1] = val), "SET_VCH$canalManualSelecionado"),
                ],
              ),
            ),
          ),
        ],
        if (!isManual) ...[
          const SizedBox(height: 8),
          _buildSliderCard("VELOCIDADE EFEITO", velocidad, (val) => setState(() => velocidad = val), "SET_VEL"),
          const SizedBox(height: 8),
          _buildSliderCard("BRILHO GERAL", brilhoGeral, (val) => setState(() => brilhoGeral = val), "SET_DIM"),
        ],
      ],
    );
  }

  Widget _buildSliderRow(String label, double val, Function(double) onCh, String cmd) {
    return Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 11)), Text("${val.toInt()}%", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]), Slider(value: val, min: 0, max: 100, divisions: 100, activeColor: Colors.amber, onChanged: onCh, onChangeEnd: (v) => enviarComando(cmd, "${v.round()}"))]);
  }

  Widget _buildSliderCard(String label, double val, Function(double) onCh, String cmd) {
    return Card(color: const Color(0xFF1E1E1E), child: Padding(padding: const EdgeInsets.all(12), child: _buildSliderRow(label, val, onCh, cmd)));
  }

  Widget _buildSimuladorPistaLed() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("ANÁLISE GERAL (PISO)", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)), DropdownButton<int>(value: tamanhoGrade, dropdownColor: const Color(0xFF1E1E1E), items: [3, 4, 5, 6].map((int i) => DropdownMenuItem(value: i, child: Text("${i}x$i  "))).toList(), onChanged: (v) => setState(() => tamanhoGrade = v!))]),
          const SizedBox(height: 12),
          Container(width: 200, height: 200, decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(8)), child: CustomPaint(painter: LedGridPainter(gridSize: tamanhoGrade, niveisCanais: niveisReaisCanais))),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: ElevatedButton(onPressed: () => enviarComando("EFEITO_PISTA", "START"), child: const Text("TESTAR PISTA"))), const SizedBox(width: 8), Expanded(child: ElevatedButton(onPressed: () => enviarComando("EFEITO_PISTA", "CLEAR"), child: const Text("APAGAR")))]),
        ],
      ),
    );
  }
}

class LedGridPainter extends CustomPainter {
  final int gridSize;
  final List<double> niveisCanais;
  LedGridPainter({required this.gridSize, required this.niveisCanais});
  @override
  void paint(Canvas canvas, Size size) {
    double sw = size.width / gridSize, sh = size.height / gridSize;
    for (int i = 0; i < gridSize * gridSize; i++) {
      int r = i ~/ gridSize, c = i % gridSize;
      int chF = (r + c) % 2 == 0 ? 0 : 2, chQ = (r + c) % 2 == 0 ? 1 : 3;
      double nf = niveisCanais[chF] / 100.0, nq = niveisCanais[chQ] / 100.0;
      final Rect rect = Rect.fromLTWH(c * sw, r * sh, sw - 2, sh - 2);
      if (nf == 0 && nq == 0) canvas.drawRect(rect, Paint()..color = Colors.grey.shade900);
      else {
        double t = (nf + nq).clamp(0.001, 2.0);
        int red = ((224 * nf + 255 * nq) / t).round(), green = ((232 * nf + 227 * nq) / t).round(), blue = ((255 * nf + 163 * nq) / t).round();
        canvas.drawRect(rect, Paint()..color = Color.fromARGB(255, red, green, blue).withOpacity((t / 1.5).clamp(0.3, 1.0)));
      }
    }
  }
  @override
  bool shouldRepaint(covariant LedGridPainter old) => old.niveisCanais != niveisCanais || old.gridSize != gridSize;
}
