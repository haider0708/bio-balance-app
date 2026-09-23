/// A private installation label, with no effect on account permissions.
abstract final class Installation {
  static const variant = String.fromEnvironment('ANDROID_INSTALLATION');
  static const label = variant == 'admin'
      ? 'BioBalance Admin'
      : variant == 'responsable'
      ? 'BioBalance Responsable'
      : variant == 'vendeur'
      ? 'BioBalance Vendeur'
      : 'BioBalance';
  static const loginHint = variant == 'admin'
      ? 'Connectez-vous avec votre compte administrateur.'
      : variant == 'responsable'
      ? 'Activez votre invitation ou connectez-vous avec votre compte responsable.'
      : variant == 'vendeur'
      ? 'Activez votre invitation ou connectez-vous avec votre compte vendeur.'
      : 'Accédez à votre espace BioBalance';
}
