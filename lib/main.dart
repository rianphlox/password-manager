import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:clipboard/clipboard.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PasswordProvider()),
      ],
      child: PasswordManagerApp(),
    ),
  );
}

class PasswordManagerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        return MaterialApp(
          title: 'QPass',
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: _getThemeMode(settingsProvider.themeMode),
          home: SplashScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }

  ThemeMode _getThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  ThemeData _buildLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: Color(0xFF1E88E5),
      scaffoldBackgroundColor: Color(0xFFF5F5F5),
      colorScheme: ColorScheme.light(
        primary: Color(0xFF1E88E5),
        secondary: Color(0xFF1E88E5),
        surface: Colors.white,
        background: Color(0xFFF5F5F5),
      ),
      cardColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.grey.withOpacity(0.3),
        foregroundColor: Colors.black,
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: Colors.black87),
        bodyMedium: TextStyle(color: Colors.black87),
        titleLarge: TextStyle(color: Colors.black87),
        titleMedium: TextStyle(color: Colors.black87),
        titleSmall: TextStyle(color: Colors.black87),
      ),
      iconTheme: IconThemeData(color: Color(0xFF1E88E5)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF1E88E5),
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Color(0xFF1E88E5),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Color(0xFF1E88E5), width: 2),
        ),
        labelStyle: TextStyle(color: Colors.grey.shade600),
        hintStyle: TextStyle(color: Colors.grey.shade500),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: Color(0xFF00C896),
      scaffoldBackgroundColor: Color(0xFF1A1A1A),
      colorScheme: ColorScheme.dark(
        primary: Color(0xFF00C896),
        secondary: Color(0xFF00C896),
        surface: Color(0xFF2A2A2A),
        background: Color(0xFF1A1A1A),
      ),
      cardColor: Color(0xFF2A2A2A),
      appBarTheme: AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        elevation: 0,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        titleLarge: TextStyle(color: Colors.white),
        titleMedium: TextStyle(color: Colors.white),
        titleSmall: TextStyle(color: Colors.white),
      ),
      iconTheme: IconThemeData(color: Colors.white70),
    );
  }
}

// Database Helper
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String dbPath = path_helper.join(await getDatabasesPath(), 'password_vault.db');
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE passwords(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        url TEXT,
        notes TEXT,
        category TEXT NOT NULL,
        isFavorite INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertPassword(Map<String, dynamic> password) async {
    final db = await database;
    return await db.insert('passwords', password);
  }

  Future<List<Map<String, dynamic>>> getPasswords() async {
    final db = await database;
    return await db.query('passwords', orderBy: 'updatedAt DESC');
  }

  Future<int> updatePassword(int id, Map<String, dynamic> password) async {
    final db = await database;
    return await db.update('passwords', password, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletePassword(int id) async {
    final db = await database;
    return await db.delete('passwords', where: 'id = ?', whereArgs: [id]);
  }
}

// Encryption Service
class EncryptionService {
  static const _storage = FlutterSecureStorage();
  static const String _keyAlias = 'encryption_key';

  static Future<String> _getOrCreateKey() async {
    String? keyValue = await _storage.read(key: _keyAlias);
    if (keyValue == null) {
      final secureKey = encrypt.Key.fromSecureRandom(32);
      keyValue = secureKey.base64;
      await _storage.write(key: _keyAlias, value: keyValue);
    }
    return keyValue;
  }

  static Future<String> encryptData(String data) async {
    final keyString = await _getOrCreateKey();
    final key = encrypt.Key.fromBase64(keyString);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypted = encrypter.encrypt(data, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  static Future<String> decryptData(String encryptedData) async {
    final keyString = await _getOrCreateKey();
    final key = encrypt.Key.fromBase64(keyString);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    
    final parts = encryptedData.split(':');
    final iv = encrypt.IV.fromBase64(parts[0]);
    final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
    
    return encrypter.decrypt(encrypted, iv: iv);
  }
}

// Password Model
class Password {
  final int? id;
  final String service;
  final String username;
  final String password;
  final String? url;
  final String? notes;
  final String category;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  Password({
    this.id,
    required this.service,
    required this.username,
    required this.password,
    this.url,
    this.notes,
    required this.category,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'service': service,
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
      'category': category,
      'isFavorite': isFavorite ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Password.fromMap(Map<String, dynamic> map) {
    return Password(
      id: map['id'],
      service: map['service'] ?? '',
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      url: map['url'],
      notes: map['notes'],
      category: map['category'] ?? 'Other',
      isFavorite: (map['isFavorite'] ?? 0) == 1,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}

// Settings Provider
class SettingsProvider with ChangeNotifier {
  static const String _autoLockKey = 'auto_lock_minutes';
  static const String _clipboardClearKey = 'clipboard_clear_seconds';
  static const String _defaultPasswordLengthKey = 'default_password_length';
  static const String _themeKey = 'theme_mode';
  static const String _defaultCategoryKey = 'default_category';
  static const String _passwordComplexityKey = 'password_complexity';

  int _autoLockMinutes = 5;
  int _clipboardClearSeconds = 30;
  int _defaultPasswordLength = 16;
  String _themeMode = 'dark';
  String _defaultCategory = 'Social';
  Map<String, bool> _passwordComplexity = {
    'uppercase': true,
    'lowercase': true,
    'numbers': true,
    'symbols': true,
  };

  // Getters
  int get autoLockMinutes => _autoLockMinutes;
  int get clipboardClearSeconds => _clipboardClearSeconds;
  int get defaultPasswordLength => _defaultPasswordLength;
  String get themeMode => _themeMode;
  String get defaultCategory => _defaultCategory;
  Map<String, bool> get passwordComplexity => _passwordComplexity;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoLockMinutes = prefs.getInt(_autoLockKey) ?? 5;
    _clipboardClearSeconds = prefs.getInt(_clipboardClearKey) ?? 30;
    _defaultPasswordLength = prefs.getInt(_defaultPasswordLengthKey) ?? 16;
    _themeMode = prefs.getString(_themeKey) ?? 'dark';
    _defaultCategory = prefs.getString(_defaultCategoryKey) ?? 'Social';
    
    _passwordComplexity = {
      'uppercase': prefs.getBool('${_passwordComplexityKey}_uppercase') ?? true,
      'lowercase': prefs.getBool('${_passwordComplexityKey}_lowercase') ?? true,
      'numbers': prefs.getBool('${_passwordComplexityKey}_numbers') ?? true,
      'symbols': prefs.getBool('${_passwordComplexityKey}_symbols') ?? true,
    };
    
    notifyListeners();
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    _autoLockMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoLockKey, minutes);
    notifyListeners();
  }

  Future<void> setClipboardClearSeconds(int seconds) async {
    _clipboardClearSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clipboardClearKey, seconds);
    notifyListeners();
  }

  Future<void> setDefaultPasswordLength(int length) async {
    _defaultPasswordLength = length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultPasswordLengthKey, length);
    notifyListeners();
  }

  Future<void> setDefaultCategory(String category) async {
    _defaultCategory = category;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultCategoryKey, category);
    notifyListeners();
  }

  Future<void> setPasswordComplexity(String type, bool enabled) async {
    _passwordComplexity[type] = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_passwordComplexityKey}_$type', enabled);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
    notifyListeners();
  }

  List<int> get autoLockOptions => [1, 5, 15, 30, -1];
  String getAutoLockDisplayText(int minutes) {
    if (minutes == -1) return 'Never';
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }

  List<int> get clipboardClearOptions => [10, 30, 60, 120];
  String getClipboardClearDisplayText(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    return '${seconds ~/ 60} minute${seconds ~/ 60 == 1 ? '' : 's'}';
  }
}

// Authentication Provider
class AuthProvider with ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const String _masterPasswordKey = 'master_password_hash';
  static const String _biometricEnabledKey = 'biometric_enabled';
  
  bool _isAuthenticated = false;
  bool _hasMasterPassword = false;
  bool _isBiometricEnabled = false;
  final LocalAuthentication _localAuth = LocalAuthentication();
  Timer? _autoLockTimer;

  bool get isAuthenticated => _isAuthenticated;
  bool get hasMasterPassword => _hasMasterPassword;
  bool get isBiometricEnabled => _isBiometricEnabled;

  AuthProvider() {
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    final masterPasswordHash = await _storage.read(key: _masterPasswordKey);
    _hasMasterPassword = masterPasswordHash != null;
    
    final prefs = await SharedPreferences.getInstance();
    _isBiometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;
    
    notifyListeners();
  }

  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> createMasterPassword(String password) async {
    try {
      final hashedPassword = _hashPassword(password);
      await _storage.write(key: _masterPasswordKey, value: hashedPassword);
      _hasMasterPassword = true;
      _isAuthenticated = true;
      _startAutoLockTimer(5);
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyMasterPassword(String password) async {
    try {
      final storedHash = await _storage.read(key: _masterPasswordKey);
      final inputHash = _hashPassword(password);
      
      if (storedHash == inputHash) {
        _isAuthenticated = true;
        _startAutoLockTimer(5);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      if (!isAvailable || !_isBiometricEnabled) return false;

      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your password vault',
        options: AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        _isAuthenticated = true;
        _startAutoLockTimer(5);
        notifyListeners();
      }

      return isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  Future<void> enableBiometric(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enable);
    _isBiometricEnabled = enable;
    notifyListeners();
  }

  Future<bool> canUseBiometric() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  void _startAutoLockTimer(int minutes) {
    _autoLockTimer?.cancel();
    if (minutes == -1) return;
    _autoLockTimer = Timer(Duration(minutes: minutes), () {
      lock();
    });
  }

  void startAutoLockTimerWithSettings(int minutes) {
    _startAutoLockTimer(minutes);
  }

  void lock() {
    _isAuthenticated = false;
    _autoLockTimer?.cancel();
    notifyListeners();
  }

  Future<void> logout() async {
    await _storage.delete(key: _masterPasswordKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricEnabledKey);
    
    _isAuthenticated = false;
    _hasMasterPassword = false;
    _isBiometricEnabled = false;
    _autoLockTimer?.cancel();
    notifyListeners();
  }
}

// Password Provider
class PasswordProvider with ChangeNotifier {
  List<Password> _passwords = [];
  List<Password> _filteredPasswords = [];
  String _searchQuery = '';
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Password> get passwords => _filteredPasswords;
  String get searchQuery => _searchQuery;

  Future<void> loadPasswords() async {
    try {
      final passwordMaps = await _db.getPasswords();
      _passwords = [];
      
      for (final map in passwordMaps) {
        try {
          final decryptedPassword = await EncryptionService.decryptData(map['password']);
          final password = Password.fromMap({
            ...map,
            'password': decryptedPassword,
          });
          _passwords.add(password);
        } catch (e) {
          print('Error decrypting password: $e');
        }
      }
      
      _applySearchFilter();
      notifyListeners();
    } catch (e) {
      print('Error loading passwords: $e');
    }
  }

  Future<bool> addPassword(Password password) async {
    try {
      final encryptedPassword = await EncryptionService.encryptData(password.password);
      final passwordMap = password.toMap();
      passwordMap['password'] = encryptedPassword;
      passwordMap.remove('id');
      
      final id = await _db.insertPassword(passwordMap);
      final newPassword = Password.fromMap({
        ...passwordMap,
        'id': id,
        'password': password.password,
      });
      
      _passwords.insert(0, newPassword);
      _applySearchFilter();
      notifyListeners();
      return true;
    } catch (e) {
      print('Error adding password: $e');
      return false;
    }
  }

  Future<bool> updatePassword(Password password) async {
    try {
      final encryptedPassword = await EncryptionService.encryptData(password.password);
      final passwordMap = password.toMap();
      passwordMap['password'] = encryptedPassword;
      
      await _db.updatePassword(password.id!, passwordMap);
      
      final index = _passwords.indexWhere((p) => p.id == password.id);
      if (index != -1) {
        _passwords[index] = password;
        _applySearchFilter();
        notifyListeners();
      }
      return true;
    } catch (e) {
      print('Error updating password: $e');
      return false;
    }
  }

  Future<bool> deletePassword(int id) async {
    try {
      await _db.deletePassword(id);
      _passwords.removeWhere((p) => p.id == id);
      _applySearchFilter();
      notifyListeners();
      return true;
    } catch (e) {
      print('Error deleting password: $e');
      return false;
    }
  }

  void searchPasswords(String query) {
    _searchQuery = query;
    _applySearchFilter();
    notifyListeners();
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredPasswords = List.from(_passwords);
    } else {
      _filteredPasswords = _passwords.where((password) =>
        password.service.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        password.username.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
  }
}

// Password Generator
class PasswordGenerator {
  static String generatePassword({
    int length = 16,
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
  }) {
    const String uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const String lowercase = 'abcdefghijklmnopqrstuvwxyz';
    const String numbers = '0123456789';
    const String symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    String chars = '';
    if (includeUppercase) chars += uppercase;
    if (includeLowercase) chars += lowercase;
    if (includeNumbers) chars += numbers;
    if (includeSymbols) chars += symbols;

    if (chars.isEmpty) return '';

    Random random = Random.secure();
    String password = '';
    
    if (includeUppercase) password += uppercase[random.nextInt(uppercase.length)];
    if (includeLowercase) password += lowercase[random.nextInt(lowercase.length)];
    if (includeNumbers) password += numbers[random.nextInt(numbers.length)];
    if (includeSymbols) password += symbols[random.nextInt(symbols.length)];
    
    for (int i = password.length; i < length; i++) {
      password += chars[random.nextInt(chars.length)];
    }

    List<String> passwordList = password.split('');
    passwordList.shuffle(random);
    return passwordList.join('');
  }

  static int calculateStrength(String password) {
    int score = 0;
    
    if (password.length >= 8) score += 25;
    if (password.length >= 12) score += 25;
    if (RegExp(r'[a-z]').hasMatch(password)) score += 10;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 10;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 10;
    if (RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<>?]').hasMatch(password)) score += 20;
    
    return score.clamp(0, 100);
  }

  static String getStrengthText(int strength) {
    if (strength < 30) return 'WEAK';
    if (strength < 60) return 'MEDIUM';
    if (strength < 80) return 'STRONG';
    return 'VERY STRONG';
  }

  static Color getStrengthColor(int strength) {
    if (strength < 30) return Colors.red;
    if (strength < 60) return Colors.orange;
    if (strength < 80) return Color(0xFF1E88E5);
    return Colors.green;
  }
}

// Splash Screen
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await DatabaseHelper.instance.database;
    await Future.delayed(Duration(seconds: 2));
    
    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      if (authProvider.hasMasterPassword) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LockScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => OnboardingScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'QPass',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
                letterSpacing: 2.0,
              ),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// Onboarding Screen
class OnboardingScreen extends StatefulWidget {
  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 40),
              Text(
                'Create Master Password',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'This password will encrypt and protect all your stored passwords. Make it strong and memorable.',
                style: TextStyle(fontSize: 16, color: Colors.grey[400]),
              ),
              SizedBox(height: 40),
              _buildPasswordField('Master Password', _passwordController, _obscurePassword, () {
                setState(() => _obscurePassword = !_obscurePassword);
              }),
              SizedBox(height: 24),
              _buildPasswordField('Confirm Password', _confirmPasswordController, _obscureConfirmPassword, () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              }),
              SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _createMasterPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Create Vault',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
              Spacer(),
              Center(
                child: Text(
                  'Your master password cannot be recovered if forgotten.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool obscure, VoidCallback toggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[400])),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light ? Colors.white : Color(0xFF2A2A2A),
            border: Theme.of(context).brightness == Brightness.light ? Border.all(color: Colors.grey.shade300) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter $label',
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              suffixIcon: IconButton(
                onPressed: toggle,
                icon: Icon(
                  obscure ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createMasterPassword() async {
    if (_passwordController.text.isEmpty) {
      _showErrorSnackBar('Please enter a master password');
      return;
    }

    if (_passwordController.text.length < 8) {
      _showErrorSnackBar('Master password must be at least 8 characters');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('Passwords do not match');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.createMasterPassword(_passwordController.text);

    if (success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MainScreen()),
      );
    } else {
      _showErrorSnackBar('Failed to create master password');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

// Lock Screen
class LockScreen extends StatefulWidget {
  @override
  _LockScreenState createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tryBiometricAuth();
  }

  Future<void> _tryBiometricAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isBiometricEnabled) {
      final success = await authProvider.authenticateWithBiometrics();
      if (success && mounted) {
        _navigateToMain();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.lock, size: 50, color: Colors.white),
              ),
              SizedBox(height: 32),
              Text(
                'Welcome Back',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(
                'Enter your master password to unlock',
                style: TextStyle(fontSize: 16, color: Colors.grey[400]),
              ),
              SizedBox(height: 40),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.light ? Colors.white : Color(0xFF2A2A2A),
                  border: Theme.of(context).brightness == Brightness.light ? Border.all(color: Colors.grey.shade300) : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Master password',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _unlock(),
                ),
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _unlock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('Unlock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              SizedBox(height: 16),
              Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  if (authProvider.isBiometricEnabled) {
                    return TextButton.icon(
                      onPressed: _tryBiometricAuth,
                      icon: Icon(Icons.fingerprint, color: Theme.of(context).colorScheme.primary),
                      label: Text('Use Biometric', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlock() async {
    if (_passwordController.text.isEmpty) return;

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifyMasterPassword(_passwordController.text);

    setState(() => _isLoading = false);

    if (success) {
      _navigateToMain();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Incorrect password'), backgroundColor: Colors.red),
      );
      _passwordController.clear();
    }
  }

  void _navigateToMain() {
    final passwordProvider = Provider.of<PasswordProvider>(context, listen: false);
    passwordProvider.loadPasswords();
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MainScreen()),
    );
  }
}

// Main Screen
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PasswordProvider>(context, listen: false).loadPasswords();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      authProvider.lock();
    } else if (state == AppLifecycleState.resumed) {
      authProvider.startAutoLockTimerWithSettings(settingsProvider.autoLockMinutes);
    }
  }

  List<Widget> get _screens => [
    PasswordListScreen(),
    PasswordGeneratorScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (!authProvider.isAuthenticated) {
          return LockScreen();
        }

        return Scaffold(
          body: Consumer<SettingsProvider>(
            builder: (context, settingsProvider, child) {
              return GestureDetector(
                onTap: () => authProvider.startAutoLockTimerWithSettings(settingsProvider.autoLockMinutes),
                child: _screens[_currentIndex],
              );
            },
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() => _currentIndex = index);
                final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
                authProvider.startAutoLockTimerWithSettings(settingsProvider.autoLockMinutes);
              },
              backgroundColor: Colors.transparent,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey[600],
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.password), label: 'Generator'),
                BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
              ],
            ),
          ),
          floatingActionButton: _currentIndex == 0
              ? FloatingActionButton(
                  onPressed: () {
                    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
                    Provider.of<AuthProvider>(context, listen: false)
                        .startAutoLockTimerWithSettings(settingsProvider.autoLockMinutes);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AddPasswordScreen()),
                    );
                  },
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Icon(Icons.add, color: Colors.white),
                )
              : null,
        );
      },
    );
  }
}

// Password List Screen
class PasswordListScreen extends StatefulWidget {
  @override
  _PasswordListScreenState createState() => _PasswordListScreenState();
}

class _PasswordListScreenState extends State<PasswordListScreen> {
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Consumer<PasswordProvider>(
      builder: (context, passwordProvider, child) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Hello User 👋',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color),
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: () {
                        Provider.of<AuthProvider>(context, listen: false).lock();
                      },
                      icon: Icon(Icons.lock, color: Colors.grey[400]),
                    ),
                  ],
                ),
                Text(
                  'Welcome back to QPass',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                ),
                SizedBox(height: 24),
                Text(
                  'Your Passwords (${passwordProvider.passwords.length})',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light ? Colors.white : Color(0xFF2A2A2A),
                    border: Theme.of(context).brightness == Brightness.light ? Border.all(color: Colors.grey.shade300) : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: passwordProvider.searchPasswords,
                    style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search passwords...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Recently Added',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[400]),
                ),
                SizedBox(height: 12),
                Expanded(
                  child: passwordProvider.passwords.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: passwordProvider.passwords.length,
                          itemBuilder: (context, index) {
                            final password = passwordProvider.passwords[index];
                            return _buildPasswordItem(password);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.security, size: 64, color: Colors.grey[600]),
          SizedBox(height: 16),
          Text('No passwords yet', style: TextStyle(fontSize: 18, color: Colors.grey[400])),
          SizedBox(height: 8),
          Text(
            'Tap the + button to add your first password',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordItem(Password password) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            password.service[0].toUpperCase(),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          password.service,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(password.username, style: TextStyle(color: Colors.grey[400])),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _copyToClipboard(password.password),
              icon: Icon(Icons.copy, color: Colors.grey[400]),
              tooltip: 'Copy password',
            ),
            IconButton(
              onPressed: () => _copyToClipboard(password.username),
              icon: Icon(Icons.person, color: Colors.grey[400]),
              tooltip: 'Copy username',
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PasswordDetailScreen(password: password),
            ),
          );
        },
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    
    await FlutterClipboard.copy(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: Duration(seconds: 2),
      ),
    );

    Timer(Duration(seconds: settingsProvider.clipboardClearSeconds), () {
      FlutterClipboard.copy('');
    });
  }
}

// Add Password Screen
class AddPasswordScreen extends StatefulWidget {
  final Password? passwordToEdit;
  AddPasswordScreen({this.passwordToEdit});

  @override
  _AddPasswordScreenState createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen> {
  final _serviceController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedCategory = 'Social';
  bool _obscurePassword = true;
  bool _isLoading = false;

  final List<String> _categories = [
    'Social', 'Work', 'Finance', 'Entertainment', 'Shopping', 'Cloud', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.passwordToEdit != null) {
      _populateFields(widget.passwordToEdit!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
        setState(() {
          _selectedCategory = settingsProvider.defaultCategory;
        });
      });
    }
  }

  void _populateFields(Password password) {
    _serviceController.text = password.service;
    _usernameController.text = password.username;
    _passwordController.text = password.password;
    _urlController.text = password.url ?? '';
    _notesController.text = password.notes ?? '';
    _selectedCategory = password.category;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.passwordToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Password' : 'Add Password',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildField('Service Name', _serviceController, 'e.g. Instagram'),
                      SizedBox(height: 16),
                      _buildCategoryField(),
                      SizedBox(height: 16),
                      _buildField('Username/Email', _usernameController, 'e.g. john@example.com'),
                      SizedBox(height: 16),
                      _buildPasswordField(),
                      SizedBox(height: 16),
                      _buildField('Website URL', _urlController, 'https://example.com', required: false),
                      SizedBox(height: 16),
                      _buildField('Notes', _notesController, 'Additional information', required: false, maxLines: 3),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _savePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isEditing ? 'Update Password' : 'Save Password',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {bool required = true, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + (required ? ' *' : ''),
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light ? Colors.white : Color(0xFF2A2A2A),
            border: Theme.of(context).brightness == Brightness.light ? Border.all(color: Colors.grey.shade300) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white),
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category *', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButton<String>(
            value: _selectedCategory,
            dropdownColor: Color(0xFF2A2A2A),
            style: TextStyle(color: Colors.white),
            underline: Container(),
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
            items: _categories.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedCategory = newValue!;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Password *', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light ? Colors.white : Color(0xFF2A2A2A),
            border: Theme.of(context).brightness == Brightness.light ? Border.all(color: Colors.grey.shade300) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white),
            onChanged: (value) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Enter password',
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey[600],
                    ),
                  ),
                  IconButton(
                    onPressed: _generatePassword,
                    icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_passwordController.text.isNotEmpty) ...[
          SizedBox(height: 8),
          Row(
            children: [
              Text('Strength: ', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              Text(
                PasswordGenerator.getStrengthText(
                  PasswordGenerator.calculateStrength(_passwordController.text),
                ),
                style: TextStyle(
                  color: PasswordGenerator.getStrengthColor(
                    PasswordGenerator.calculateStrength(_passwordController.text),
                  ),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _generatePassword() {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final complexity = settingsProvider.passwordComplexity;
    
    final generatedPassword = PasswordGenerator.generatePassword(
      length: settingsProvider.defaultPasswordLength,
      includeUppercase: complexity['uppercase'] ?? true,
      includeLowercase: complexity['lowercase'] ?? true,
      includeNumbers: complexity['numbers'] ?? true,
      includeSymbols: complexity['symbols'] ?? true,
    );
    setState(() {
      _passwordController.text = generatedPassword;
    });
  }

  Future<void> _savePassword() async {
    if (_serviceController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill in all required fields'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final passwordProvider = Provider.of<PasswordProvider>(context, listen: false);
    final now = DateTime.now();

    final password = Password(
      id: widget.passwordToEdit?.id,
      service: _serviceController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      url: _urlController.text.isEmpty ? null : _urlController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      category: _selectedCategory,
      createdAt: widget.passwordToEdit?.createdAt ?? now,
      updatedAt: now,
    );

    bool success;
    if (widget.passwordToEdit != null) {
      success = await passwordProvider.updatePassword(password);
    } else {
      success = await passwordProvider.addPassword(password);
    }

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.passwordToEdit != null ? 'Password updated successfully' : 'Password saved successfully'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save password'), backgroundColor: Colors.red),
      );
    }
  }
}

// Password Detail Screen
class PasswordDetailScreen extends StatefulWidget {
  final Password password;
  PasswordDetailScreen({required this.password});

  @override
  _PasswordDetailScreenState createState() => _PasswordDetailScreenState();
}

class _PasswordDetailScreenState extends State<PasswordDetailScreen> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.password.service, style: TextStyle(color: Colors.white)),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: () => _editPassword(),
            icon: Icon(Icons.edit, color: Colors.white),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _showDeleteDialog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            icon: Icon(Icons.more_vert, color: Colors.white),
            color: Color(0xFF2A2A2A),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    widget.password.service[0].toUpperCase(),
                    style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(height: 32),
              _buildDetailItem('Service', widget.password.service),
              SizedBox(height: 16),
              _buildDetailItem('Username', widget.password.username),
              SizedBox(height: 16),
              _buildPasswordItem(),
              if (widget.password.url != null && widget.password.url!.isNotEmpty) ...[
                SizedBox(height: 16),
                _buildDetailItem('Website URL', widget.password.url!),
              ],
              SizedBox(height: 16),
              _buildDetailItem('Category', widget.password.category),
              if (widget.password.notes != null && widget.password.notes!.isNotEmpty) ...[
                SizedBox(height: 16),
                _buildDetailItem('Notes', widget.password.notes!),
              ],
              SizedBox(height: 16),
              _buildDetailItem('Last Updated', _formatDate(widget.password.updatedAt)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(value, style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              IconButton(
                onPressed: () => _copyToClipboard(value),
                icon: Icon(Icons.copy, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordItem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Password', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _showPassword ? widget.password.password : '••••••••',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: _showPassword ? 'monospace' : null,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[400],
                ),
              ),
              IconButton(
                onPressed: () => _copyToClipboard(widget.password.password),
                icon: Icon(Icons.copy, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(String text) async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    
    await FlutterClipboard.copy(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: Duration(seconds: 2),
      ),
    );

    Timer(Duration(seconds: settingsProvider.clipboardClearSeconds), () {
      FlutterClipboard.copy('');
    });
  }

  void _editPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddPasswordScreen(passwordToEdit: widget.password),
      ),
    ).then((_) {
      setState(() {});
    });
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Delete Password', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete the password for "${widget.password.service}"? This action cannot be undone.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePassword();
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePassword() async {
    final passwordProvider = Provider.of<PasswordProvider>(context, listen: false);
    final success = await passwordProvider.deletePassword(widget.password.id!);
    
    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password deleted successfully'), backgroundColor: Theme.of(context).colorScheme.primary),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete password'), backgroundColor: Colors.red),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// Password Generator Screen
class PasswordGeneratorScreen extends StatefulWidget {
  @override
  _PasswordGeneratorScreenState createState() => _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState extends State<PasswordGeneratorScreen> {
  int _length = 16;
  String _password = '';
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final complexity = settingsProvider.passwordComplexity;
      
      setState(() {
        _length = settingsProvider.defaultPasswordLength;
        _includeUppercase = complexity['uppercase'] ?? true;
        _includeLowercase = complexity['lowercase'] ?? true;
        _includeNumbers = complexity['numbers'] ?? true;
        _includeSymbols = complexity['symbols'] ?? true;
      });
      _generatePassword();
    });
  }

  void _generatePassword() {
    setState(() {
      _password = PasswordGenerator.generatePassword(
        length: _length,
        includeUppercase: _includeUppercase,
        includeLowercase: _includeLowercase,
        includeNumbers: _includeNumbers,
        includeSymbols: _includeSymbols,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final strength = PasswordGenerator.calculateStrength(_password);
    
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Password Generator',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            SizedBox(height: 8),
            Text(
              'Generate secure passwords',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            SizedBox(height: 24),
            Text(
              PasswordGenerator.getStrengthText(strength),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: PasswordGenerator.getStrengthColor(strength),
              ),
            ),
            SizedBox(height: 16),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: PasswordGenerator.getStrengthColor(strength), width: 4),
                borderRadius: BorderRadius.circular(60),
                color: Color(0xFF2A2A2A),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Length', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                  Text('$_length', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    if (_length > 4) {
                      setState(() => _length--);
                      _generatePassword();
                    }
                  },
                  icon: Icon(Icons.remove, color: Theme.of(context).colorScheme.primary),
                ),
                SizedBox(width: 32),
                IconButton(
                  onPressed: () {
                    if (_length < 128) {
                      setState(() => _length++);
                      _generatePassword();
                    }
                  },
                  icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                ),
                SizedBox(width: 32),
                IconButton(
                  onPressed: _generatePassword,
                  icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildToggleOption('Uppercase (A-Z)', _includeUppercase, (value) {
                      setState(() => _includeUppercase = value);
                      _generatePassword();
                    }),
                    _buildToggleOption('Lowercase (a-z)', _includeLowercase, (value) {
                      setState(() => _includeLowercase = value);
                      _generatePassword();
                    }),
                    _buildToggleOption('Numbers (0-9)', _includeNumbers, (value) {
                      setState(() => _includeNumbers = value);
                      _generatePassword();
                    }),
                    _buildToggleOption('Symbols (!@#)', _includeSymbols, (value) {
                      setState(() => _includeSymbols = value);
                      _generatePassword();
                    }),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _password,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _copyPassword(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      minimumSize: Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Copy Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleOption(String title, bool value, Function(bool) onChanged) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
            activeTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  void _copyPassword() async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    
    await FlutterClipboard.copy(_password);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Password copied'), backgroundColor: Theme.of(context).colorScheme.primary),
    );
    
    Timer(Duration(seconds: settingsProvider.clipboardClearSeconds), () {
      FlutterClipboard.copy('');
    });
  }
}

// Profile Screen
class ProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, PasswordProvider>(
      builder: (context, authProvider, passwordProvider, child) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      'Profile',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen()));
                      },
                      icon: Icon(Icons.settings, color: Colors.grey[400]),
                    ),
                  ],
                ),
                SizedBox(height: 40),
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text('Q', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: 16),
                Text(
                  'QPass User',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color),
                ),
                SizedBox(height: 8),
                Text(
                  '${passwordProvider.passwords.length} passwords stored',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                ),
                SizedBox(height: 40),
                _buildMenuOption(
                  context,
                  'Security',
                  'Biometric & auto-lock settings',
                  Icons.security,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SecurityScreen()),
                  ),
                ),
                _buildMenuOption(
                  context,
                  'Settings',
                  'App preferences & themes',
                  Icons.settings,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SettingsScreen()),
                  ),
                ),
                Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => _logout(context, authProvider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Clear All Data & Reset', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuOption(BuildContext context, String title, String subtitle, IconData icon, {required VoidCallback onTap}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          radius: 20,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400])),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
        onTap: onTap,
      ),
    );
  }

  Future<void> _logout(BuildContext context, AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Clear All Data', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete all your stored passwords and reset QPass. This action cannot be undone.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear All Data', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('passwords');
      
      await authProvider.logout();
      
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
        (route) => false,
      );
    }
  }
}

// Security Screen
class SecurityScreen extends StatefulWidget {
  @override
  _SecurityScreenState createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer3<SettingsProvider, AuthProvider, PasswordProvider>(
      builder: (context, settingsProvider, authProvider, passwordProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Security', style: TextStyle(color: Colors.white)),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Authentication'),
                _buildBiometricSetting(authProvider),
                _buildAutoLockSetting(settingsProvider, authProvider),
                _buildListTile(
                  'Change Master Password',
                  'Update your master password',
                  Icons.key,
                  onTap: () => _showChangeMasterPassword(context, authProvider),
                ),
                
                SizedBox(height: 24),
                
                _buildSectionHeader('Privacy'),
                _buildClipboardSetting(settingsProvider),
                _buildListTile(
                  'Screen Recording Protection',
                  'Hide content during screen recording',
                  Icons.screen_lock_portrait,
                  showArrow: false,
                ),
                
                SizedBox(height: 24),
                
                _buildSectionHeader('Vault Security'),
                _buildListTile(
                  'Password Health Check',
                  'Check for weak and duplicate passwords',
                  Icons.health_and_safety,
                  onTap: () => _showPasswordHealth(context, passwordProvider),
                ),
                _buildListTile(
                  'Security Audit',
                  'Review security recommendations',
                  Icons.security,
                  onTap: () => _showSecurityAudit(context, passwordProvider),
                ),
                _buildListTile(
                  'Failed Login Attempts',
                  'View unauthorized access attempts',
                  Icons.warning,
                  onTap: () => _showComingSoon(context, 'Failed login tracking'),
                ),
                
                SizedBox(height: 24),
                
                _buildSectionHeader('Backup & Recovery'),
                _buildListTile(
                  'Export Encrypted Vault',
                  'Create secure backup of your passwords',
                  Icons.download,
                  onTap: () => _exportVault(context, passwordProvider),
                ),
                _buildListTile(
                  'Emergency Access',
                  'Setup trusted contact for emergencies',
                  Icons.emergency,
                  onTap: () => _showComingSoon(context, 'Emergency access'),
                ),
                
                SizedBox(height: 32),
                
                _buildDangerZone(context, authProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildListTile(String title, String subtitle, IconData icon, {VoidCallback? onTap, bool showArrow = true}) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: showArrow ? Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildBiometricSetting(AuthProvider authProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.fingerprint, color: Theme.of(context).colorScheme.primary),
        title: Text('Biometric Authentication', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text('Unlock with fingerprint or face ID', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: Switch(
          value: authProvider.isBiometricEnabled,
          onChanged: (value) => _toggleBiometric(context, authProvider, value),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildAutoLockSetting(SettingsProvider settingsProvider, AuthProvider authProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.timer, color: Theme.of(context).colorScheme.primary),
        title: Text('Auto-lock Timer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(
          settingsProvider.getAutoLockDisplayText(settingsProvider.autoLockMinutes),
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
        onTap: () => _showAutoLockOptions(context, settingsProvider, authProvider),
      ),
    );
  }

  Widget _buildClipboardSetting(SettingsProvider settingsProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.content_paste, color: Theme.of(context).colorScheme.primary),
        title: Text('Clipboard Auto-Clear', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(
          settingsProvider.getClipboardClearDisplayText(settingsProvider.clipboardClearSeconds),
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
        onTap: () => _showClipboardOptions(context, settingsProvider),
      ),
    );
  }

  Widget _buildDangerZone(BuildContext context, AuthProvider authProvider) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Danger Zone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _confirmClearAllData(context, authProvider),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Clear All Data', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAutoLockOptions(BuildContext context, SettingsProvider settingsProvider, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Auto-lock Timer', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: settingsProvider.autoLockOptions.map((minutes) {
            return RadioListTile<int>(
              value: minutes,
              groupValue: settingsProvider.autoLockMinutes,
              onChanged: (value) {
                settingsProvider.setAutoLockMinutes(value!);
                authProvider.startAutoLockTimerWithSettings(value);
                Navigator.pop(context);
              },
              title: Text(
                settingsProvider.getAutoLockDisplayText(minutes),
                style: TextStyle(color: Colors.white),
              ),
              activeColor: Theme.of(context).colorScheme.primary,
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showClipboardOptions(BuildContext context, SettingsProvider settingsProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Clipboard Auto-Clear', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: settingsProvider.clipboardClearOptions.map((seconds) {
            return RadioListTile<int>(
              value: seconds,
              groupValue: settingsProvider.clipboardClearSeconds,
              onChanged: (value) {
                settingsProvider.setClipboardClearSeconds(value!);
                Navigator.pop(context);
              },
              title: Text(
                settingsProvider.getClipboardClearDisplayText(seconds),
                style: TextStyle(color: Colors.white),
              ),
              activeColor: Theme.of(context).colorScheme.primary,
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _toggleBiometric(BuildContext context, AuthProvider authProvider, bool enable) async {
    if (enable) {
      final canUseBiometric = await authProvider.canUseBiometric();
      if (!canUseBiometric) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biometric authentication not available'), backgroundColor: Colors.orange),
        );
        return;
      }

      final success = await authProvider.authenticateWithBiometrics();
      if (success) {
        await authProvider.enableBiometric(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biometric authentication enabled'), backgroundColor: Theme.of(context).colorScheme.primary),
        );
      }
    } else {
      await authProvider.enableBiometric(false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Biometric authentication disabled'), backgroundColor: Theme.of(context).colorScheme.primary),
      );
    }
  }

  void _showChangeMasterPassword(BuildContext context, AuthProvider authProvider) {
    _showComingSoon(context, 'Change master password');
  }

  void _showPasswordHealth(BuildContext context, PasswordProvider provider) {
    final passwords = provider.passwords;
    final weakPasswords = passwords.where((p) => 
      PasswordGenerator.calculateStrength(p.password) < 60
    ).length;
    
    final duplicatePasswords = <String, int>{};
    for (final password in passwords) {
      duplicatePasswords[password.password] = (duplicatePasswords[password.password] ?? 0) + 1;
    }
    final duplicates = duplicatePasswords.values.where((count) => count > 1).length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Password Health Report', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHealthItem('Total passwords', '${passwords.length}', Colors.white),
            _buildHealthItem('Weak passwords', '$weakPasswords', weakPasswords > 0 ? Colors.orange : Theme.of(context).colorScheme.primary),
            _buildHealthItem('Duplicate passwords', '$duplicates', duplicates > 0 ? Colors.red : Theme.of(context).colorScheme.primary),
            SizedBox(height: 16),
            Text(
              weakPasswords > 0 || duplicates > 0 
                ? 'Consider updating weak or duplicate passwords for better security.'
                : 'Excellent! Your passwords are secure.',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showSecurityAudit(BuildContext context, PasswordProvider provider) {
    final passwords = provider.passwords;
    final recommendations = <String>[];
    
    if (passwords.any((p) => PasswordGenerator.calculateStrength(p.password) < 60)) {
      recommendations.add('Update weak passwords');
    }
    
    final duplicates = <String, int>{};
    for (final password in passwords) {
      duplicates[password.password] = (duplicates[password.password] ?? 0) + 1;
    }
    if (duplicates.values.any((count) => count > 1)) {
      recommendations.add('Replace duplicate passwords');
    }
    
    if (passwords.any((p) => DateTime.now().difference(p.updatedAt).inDays > 365)) {
      recommendations.add('Update old passwords (1+ years)');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Security Audit', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recommendations.isEmpty) ...[
              Icon(Icons.verified, color: Theme.of(context).colorScheme.primary, size: 32),
              SizedBox(height: 8),
              Text('Your vault security looks excellent!', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ] else ...[
              Text('Security Recommendations:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              ...recommendations.map((rec) => Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text(rec, style: TextStyle(color: Colors.grey[400]))),
                  ],
                ),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthItem(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _exportVault(BuildContext context, PasswordProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Export Vault', style: TextStyle(color: Colors.white)),
        content: Text(
          'Export functionality will create an encrypted backup of your password vault. This feature will be available in a future update.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon in future updates!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _confirmClearAllData(BuildContext context, AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Clear All Data', style: TextStyle(color: Colors.red)),
        content: Text(
          'This will permanently delete all your stored passwords and reset QPass. This action cannot be undone.\n\nAre you absolutely sure?',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear All Data', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('passwords');
      
      await authProvider.logout();
      
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
        (route) => false,
      );
    }
  }
}

// Settings Screen
class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer3<SettingsProvider, AuthProvider, PasswordProvider>(
      builder: (context, settingsProvider, authProvider, passwordProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Settings', style: TextStyle(color: Colors.white)),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Appearance'),
                _buildThemeSetting(settingsProvider),
                _buildListTile(
                  'App Language',
                  'English (US)',
                  Icons.language,
                  onTap: () => _showComingSoon(context, 'Language selection'),
                ),
                _buildListTile(
                  'Font Size',
                  'Medium',
                  Icons.text_fields,
                  onTap: () => _showComingSoon(context, 'Font size options'),
                ),
                
                SizedBox(height: 24),
                
                _buildSectionHeader('Password Defaults'),
                _buildPasswordLengthSetting(settingsProvider),
                _buildPasswordComplexitySetting(settingsProvider),
                _buildDefaultCategorySetting(settingsProvider),
                
                SizedBox(height: 24),
                
                _buildSectionHeader('Notifications'),
                _buildNotificationSetting('Security Alerts', 'Get notified of security issues', true),
                _buildNotificationSetting('Backup Reminders', 'Remind me to backup my vault', false),
                _buildNotificationSetting('Password Expiry', 'Notify when passwords are old', false),
                
                SizedBox(height: 24),
                
                _buildSectionHeader('Data & Storage'),
                _buildListTile(
                  'Vault Statistics',
                  'View your password analytics',
                  Icons.analytics,
                  onTap: () => _showVaultStats(context, passwordProvider),
                ),
                _buildListTile(
                  'Storage Usage',
                  'Manage app storage and cache',
                  Icons.storage,
                  onTap: () => _showStorageInfo(context),
                ),
                _buildListTile(
                  'Import Passwords',
                  'Import from other password managers',
                  Icons.upload,
                  onTap: () => _showComingSoon(context, 'Import functionality'),
                ),
                
                SizedBox(height: 24),
                
                _buildSectionHeader('About'),
                _buildListTile('App Version', 'QPass v1.0.0', Icons.info, showArrow: false),
                _buildListTile(
                  'Privacy Policy',
                  'View privacy policy and terms',
                  Icons.privacy_tip,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => PrivacyPolicyScreen()),
                  ),
                ),
                _buildListTile(
                  'Rate QPass',
                  'Leave a review on the App Store',
                  Icons.star,
                  onTap: () => _showComingSoon(context, 'App Store rating'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildListTile(String title, String subtitle, IconData icon, {VoidCallback? onTap, bool showArrow = true}) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: showArrow ? Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildThemeSetting(SettingsProvider settingsProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(_getThemeIcon(settingsProvider.themeMode), color: Theme.of(context).colorScheme.primary),
        title: Text('Theme', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(_getThemeDisplayText(settingsProvider.themeMode), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
        onTap: () => _showThemeOptions(context, settingsProvider),
      ),
    );
  }

  Widget _buildNotificationSetting(String title, String subtitle, bool enabled) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.notifications, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: Switch(
          value: enabled,
          onChanged: (value) => _showComingSoon(context, 'Notification settings'),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildPasswordLengthSetting(SettingsProvider settingsProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.straighten, color: Theme.of(context).colorScheme.primary),
        title: Text('Default Password Length', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text('${settingsProvider.defaultPasswordLength} characters', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                if (settingsProvider.defaultPasswordLength > 8) {
                  settingsProvider.setDefaultPasswordLength(settingsProvider.defaultPasswordLength - 1);
                }
              },
              icon: Icon(Icons.remove, color: Colors.grey[400]),
            ),
            Text('${settingsProvider.defaultPasswordLength}', style: TextStyle(color: Colors.white)),
            IconButton(
              onPressed: () {
                if (settingsProvider.defaultPasswordLength < 128) {
                  settingsProvider.setDefaultPasswordLength(settingsProvider.defaultPasswordLength + 1);
                }
              },
              icon: Icon(Icons.add, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordComplexitySetting(SettingsProvider settingsProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
        title: Text('Password Complexity', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text('Default character sets for new passwords', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        iconColor: Colors.grey[400],
        collapsedIconColor: Colors.grey[400],
        children: [
          _buildComplexityOption('Uppercase Letters (A-Z)', 'uppercase', settingsProvider),
          _buildComplexityOption('Lowercase Letters (a-z)', 'lowercase', settingsProvider),
          _buildComplexityOption('Numbers (0-9)', 'numbers', settingsProvider),
          _buildComplexityOption('Symbols (!@#\$)', 'symbols', settingsProvider),
        ],
      ),
    );
  }

  Widget _buildComplexityOption(String title, String key, SettingsProvider settingsProvider) {
    return ListTile(
      title: Text(title, style: TextStyle(color: Colors.white, fontSize: 14)),
      trailing: Switch(
        value: settingsProvider.passwordComplexity[key] ?? false,
        onChanged: (value) => settingsProvider.setPasswordComplexity(key, value),
        activeColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildDefaultCategorySetting(SettingsProvider settingsProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.category, color: Theme.of(context).colorScheme.primary),
        title: Text('Default Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(settingsProvider.defaultCategory, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
        onTap: () => _showCategoryOptions(context, settingsProvider),
      ),
    );
  }


  void _showCategoryOptions(BuildContext context, SettingsProvider settingsProvider) {
    final categories = ['Social', 'Work', 'Finance', 'Entertainment', 'Shopping', 'Cloud', 'Other'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Default Category', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: categories.map((category) {
            return RadioListTile<String>(
              value: category,
              groupValue: settingsProvider.defaultCategory,
              onChanged: (value) {
                settingsProvider.setDefaultCategory(value!);
                Navigator.pop(context);
              },
              title: Text(category, style: TextStyle(color: Colors.white)),
              activeColor: Theme.of(context).colorScheme.primary,
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showVaultStats(BuildContext context, PasswordProvider provider) {
    final passwords = provider.passwords;
    final categoryStats = <String, int>{};
    
    for (final password in passwords) {
      categoryStats[password.category] = (categoryStats[password.category] ?? 0) + 1;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Vault Statistics', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total passwords: ${passwords.length}', style: TextStyle(color: Colors.white, fontSize: 16)),
            SizedBox(height: 16),
            Text('By category:', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            ...categoryStats.entries.map((entry) => Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key, style: TextStyle(color: Colors.white)),
                  Text('${entry.value}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showStorageInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        title: Text('Storage Usage', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStorageItem('Encrypted passwords', '~2.4 KB'),
            _buildStorageItem('App settings', '~1.1 KB'),
            _buildStorageItem('Cache', '~512 B'),
            Divider(color: Colors.grey[600]),
            _buildStorageItem('Total storage', '~4.0 KB', isTotal: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageItem(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? Colors.white : Colors.grey[400],
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isTotal ? Theme.of(context).colorScheme.primary : Colors.white,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  String _getThemeDisplayText(String themeMode) {
    switch (themeMode) {
      case 'light':
        return 'Light Mode';
      case 'dark':
        return 'Dark Mode';
      case 'system':
        return 'Follow System';
      default:
        return 'Dark Mode';
    }
  }

  IconData _getThemeIcon(String themeMode) {
    switch (themeMode) {
      case 'light':
        return Icons.light_mode;
      case 'dark':
        return Icons.dark_mode;
      case 'system':
        return Icons.brightness_auto;
      default:
        return Icons.dark_mode;
    }
  }

  void _showThemeOptions(BuildContext context, SettingsProvider settingsProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Theme', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption('Light', 'light', settingsProvider),
            _buildThemeOption('Dark', 'dark', settingsProvider),
            _buildThemeOption('Follow System', 'system', settingsProvider),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(String title, String value, SettingsProvider settingsProvider) {
    return RadioListTile<String>(
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      value: value,
      groupValue: settingsProvider.themeMode,
      onChanged: (String? newValue) {
        if (newValue != null) {
          settingsProvider.setThemeMode(newValue);
          Navigator.pop(context);
        }
      },
      activeColor: Theme.of(context).colorScheme.primary,
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon in future updates!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

// Privacy Policy Screen
class PrivacyPolicyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Privacy Policy'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QPass Privacy Policy',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'QPass respects your privacy and is committed to protecting your personal information.',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 24),

              _buildSection(
                context,
                'Information We Collect',
                'We collect only minimal, non-identifiable information such as device type, operating system, app version, and anonymous usage statistics. QPass does not collect or store your passwords or personal data.',
              ),

              _buildSection(
                context,
                'How We Use Information',
                'Collected information is used solely to:\n\n• Maintain and improve app performance\n• Enhance security and user experience\n• Provide updates or support when requested\n\nWe never sell, rent, or share your data with third parties.',
              ),

              _buildSection(
                context,
                'Data Security',
                '• All saved passwords are encrypted locally using AES-256-bit encryption.\n• Your master password is never stored or transmitted.\n• If cloud backup or sync is used, encryption happens before data leaves your device.',
              ),

              _buildSection(
                context,
                'Third-Party Services',
                'We may use trusted services for analytics or crash reporting, but they cannot access your encrypted data.',
              ),

              _buildSection(
                context,
                'Your Rights',
                'You may:\n\n• Access, correct, or delete your stored data\n• Export your data\n• Disable cloud or sync features anytime',
              ),

              _buildSection(
                context,
                'Policy Updates',
                'We may update this Privacy Policy periodically. Major updates will be communicated within the app. Your continued use of QPass after updates means you accept the revised policy.',
              ),

              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          content,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.9),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }
}