import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'services/bpjs_api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = BpjsApiService();
  await apiService.init();

  runApp(
    ChangeNotifierProvider<BpjsApiService>.value(
      value: apiService,
      child: const FristaMobileApp(),
    ),
  );
}

class FristaMobileApp extends StatelessWidget {
  const FristaMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF088A76);

    return MaterialApp(
      title: 'FRISTA Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const LoginScreen(autoLogin: true),
    );
  }
}
