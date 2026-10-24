import 'package:flutter/material.dart';
import 'package:routeros_api/routeros_api.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MikroTikApp());

class MikroTikApp extends StatelessWidget {
  const MikroTikApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MikroTik Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ConnectionScreen(),
    );
  }
}

// ================= شاشة الاتصال بالسيرفر =================
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({Key? key}) : super(key: key);

  @override
  _ConnectionScreenState createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _ipController = TextEditingController(text: '10.0.0.2');
  final _userController = TextEditingController(text: 'admin');
  final _passController = TextEditingController();
  bool _isLoading = false;

  Future<void> _connectToRouter(BuildContext context) async {
    setState(() => _isLoading = true);
    try {
      var conn = await RoutersApi.connect(
        _ipController.text,
        8728,
        _userController.text,
        _passController.text,
      );

      setState(() => _isLoading = false);
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => DashboardScreen(connection: conn)),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاتصال بالميكروتك: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول لسيرفر الميكروتك')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _ipController, decoration: const InputDecoration(labelText: 'IP Address')),
            TextField(controller: _userController, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: _passController, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: () => _connectToRouter(context),
                    child: const Text('اتصال بالسيرفر'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ================= لوحة التحكم الرئيسية =================
class DashboardScreen extends StatefulWidget {
  final RoutersApi connection;
  const DashboardScreen({Key? key, required this.connection}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List activeUsers = [];
  bool _fetching = true;

  @override
  void initState() {
    super.initState();
    _getActiveUsers();
  }

  Future<void> _getActiveUsers() async {
    try {
      var query = await widget.connection.talk(['/ip/hotspot/active/print']);
      setState(() {
        activeUsers = query;
        _fetching = false;
      });
    } catch (e) {
      setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراقبة مستخدمي الميكروتك'),
        actions: [
          IconButton(
            icon: const Icon(Icons.card_membership),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserManagerScreen(connection: widget.connection)),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _getActiveUsers),
        ],
      ),
      body: _fetching
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: activeUsers.length,
              itemBuilder: (context, index) {
                var user = activeUsers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: const Icon(Icons.person, color: Colors.blue),
                    title: Text('المستخدم: ${user['user'] ?? 'غير معروف'}'),
                    subtitle: Text('الآيبي: ${user['address']}\nالمدة: ${user['uptime']}'),
                    isThreeLine: true,
                    trailing: Text('التحميل: ${user['bytes-out'] ?? '0'} بايت'),
                  ),
                );
              },
            ),
    );
  }
}

// ================= شاشة توليد وطباعة الكروت =================
class UserManagerScreen extends StatefulWidget {
  final RoutersApi connection;
  const UserManagerScreen({Key? key, required this.connection}) : super(key: key);

  @override
  _UserManagerScreenState createState() => _UserManagerScreenState();
}

class _UserManagerScreenState extends State<UserManagerScreen> {
  List profiles = [];
  List generatedVouchers = [];
  bool _isLoading = false;
  String? selectedProfile;
  final TextEditingController _countController = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _fetchUserProfiles();
  }

  Future<void> _fetchUserProfiles() async {
    try {
      var result = await widget.connection.talk(['/ip/hotspot/user/profile/print']);
      setState(() {
        profiles = result;
        if (profiles.isNotEmpty) {
          selectedProfile = profiles[0]['name'];
        }
      });
    } catch (e) {
      print("خطأ في جلب البروفايلات: $e");
    }
  }

  Future<void> _generateVouchers() async {
    setState(() => _isLoading = true);
    try {
      int count = int.parse(_countController.text);
      List tempVouchers = [];

      for (int i = 0; i < count; i++) {
        String username = 'u${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}$i';
        String password = 'p${1000 + i}';

        await widget.connection.talk([
          '/ip/hotspot/user/add',
          '=name=$username',
          '=password=$password',
          '=profile=${selectedProfile ?? 'default'}',
        ]);

        tempVouchers.add({'username': username, 'password': password});
      }

      setState(() {
        generatedVouchers = tempVouchers;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم توليد الكروت بنجاح!')),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل التوليد: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('توليد كروت الميكروتك')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اختر بروفايل الكروت:', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              isExpanded: true,
              value: selectedProfile,
              items: profiles.map((p) {
                return DropdownMenuItem<String>(
                  value: p['name'] as String?,
                  child: Text(p['name'] ?? 'بدون اسم'),
                );
              }).toList(),
              onChanged: (val) => setState(() => selectedProfile = val),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد الكروت'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _generateVouchers,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('توليد الكروت الآن'),
              ),
            ),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Text('الكروت المولدة (${generatedVouchers.length}):', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (generatedVouchers.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PrinterManagerScreen(generatedVouchers: generatedVouchers),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('الذهاب للطباعة'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: generatedVouchers.length,
                itemBuilder: (context, index) {
                  var v = generatedVouchers[index];
                  return Card(
                    child: ListTile(
                      title: Text('المستخدم: ${v['username']}'),
                      subtitle: Text('كلمة المرور: ${v['password']}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= شاشة طباعة البلوتوث =================
class PrinterManagerScreen extends StatefulWidget {
  final List generatedVouchers;
  const PrinterManagerScreen({Key? key, required this.generatedVouchers}) : super(key: key);

  @override
  _PrinterManagerScreenState createState() => _PrinterManagerScreenState();
}

class _PrinterManagerScreenState extends State<PrinterManagerScreen> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    bool? isConnected = await bluetooth.isConnected;
    List<BluetoothDevice> devices = [];
    try {
      devices = await bluetooth.getBondedDevices();
    } catch (e) {
      print("خطأ: $e");
    }

    setState(() {
      _devices = devices;
      _isConnected = isConnected ?? false;
    });
  }

  void _connectToPrinter(BluetoothDevice device) async {
    setState(() => _isConnecting = true);
    try {
      await bluetooth.connect(device);
      setState(() {
        _selectedDevice = device;
        _isConnected = true;
        _isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الاتصال بالطابعة: ${device.name}')),
      );
    } catch (e) {
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاتصال: $e')),
      );
    }
  }

  void _printVouchersTicket() async {
    if (_isConnected) {
      bluetooth.printCustom("--- شبكة عبود نت ---", 1, 1);
      bluetooth.printNewLine();

      for (var voucher in widget.generatedVouchers) {
        bluetooth.printCustom("--------------------------------", 0, 1);
        bluetooth.printCustom("Username: ${voucher['username']}", 1, 0);
        bluetooth.printCustom("Password: ${voucher['password']}", 1, 0);
        bluetooth.printCustom("--------------------------------", 0, 1);
        bluetooth.printNewLine();
      }
      
      bluetooth.printCut();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الطباعة بنجاح!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء الاتصال بالطابعة أولاً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طابعة البلوتوث الحرارية')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اختر الطابعة المقترنة:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(
              height: 150,
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  BluetoothDevice device = _devices[index];
                  return ListTile(
                    leading: const Icon(Icons.print),
                    title: Text(device.name ?? "طابعة"),
                    subtitle: Text(device.address ?? ""),
                    trailing: ElevatedButton(
                      onPressed: _isConnecting ? null : () => _connectToPrinter(device),
                      child: Text(_selectedDevice?.address == device.address && _isConnected ? 'متصل' : 'اتصال'),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Center(
              child: Text(
                _isConnected ? 'الحالة: متصل ✅' : 'الحالة: غير متصل ❌',
                style: TextStyle(color: _isConnected ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: _isConnected ? _printVouchersTicket : null,
                icon: const Icon(Icons.print),
                label: Text('طباعة الكروت (${widget.generatedVouchers.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
