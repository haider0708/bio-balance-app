import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';
import '../services/api/generated/models.dart';

class IdentityRepository {
  final ApiClient api;
  IdentityRepository(this.api);
  Future<Json> login(String email, String password, String otp) async =>
      (await api.identityLogin(
        body: IdentityLoginRequestDto(
          email: email.trim(),
          password: password,
          otp: otp.isEmpty ? null : otp,
        ),
      )).toJson();
  Future<void> activate(String token, String password, String name) async {
    await api.identityActivate(
      body: IdentityActivateRequestDto(
        token: token,
        password: password,
        name: name,
      ),
    );
  }

  Future<void> forgot(String email) async {
    await api.identityForgot(body: IdentityForgotRequestDto(email: email));
  }

  Future<void> reset(String token, String password) async {
    await api.identityReset(
      body: IdentityResetRequestDto(token: token, password: password),
    );
  }
}
