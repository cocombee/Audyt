import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'authentication_page.dart';
import 'google_account_session.dart';

Future<void> showPasswordChange(
  BuildContext context,
  GoogleAccountSession session,
) => showDialog<void>(
  context: context,
  builder: (_) => _PasswordChangeDialog(session: session),
);

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog({required this.session});
  final GoogleAccountSession session;
  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  String? error;
  bool saving = false;
  @override
  void dispose() {
    current.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(() {
      saving = true;
      error = null;
    });
    await widget.session.changePassword(current.text, password.text);
    if (!mounted) return;
    if (widget.session.error != null) {
      setState(() {
        error = widget.session.error;
        saving = false;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(
      String label,
      String key,
      TextEditingController controller,
      String? Function(String?) validate,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AccountingTypography.fieldLabel(context)),
        const SizedBox(height: 8),
        AuthTextField(
          fieldKey: ValueKey(key),
          controller: controller,
          hint: 'Enter $label',
          secret: true,
          limit: 128,
          enabled: !saving,
          validator: validate,
        ),
        const SizedBox(height: 20),
      ],
    );
    return AccountingDialog.alert(
      context,
      title: 'Change Password',
      description: 'Saving signs you out of all sessions. Sign in again with your new password.',
      maxContentWidth: 420,
      contentInset: 20,
      formFooter: true,
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (error != null)
                AccountingAlert.build(
                  context,
                  title: 'Password Change Needs Attention',
                  description: error!,
                  destructive: true,
                  bottomGap: 20,
                ),
              field(
                'Current Password',
                'password-current',
                current,
                (v) =>
                    (v ?? '').isEmpty ? 'Enter your current password.' : null,
              ),
              field(
                'New Password',
                'password-new',
                password,
                (v) =>
                    (v ?? '').runes.length < 15 || (v ?? '').runes.length > 128
                    ? 'Use 15 to 128 characters.'
                    : null,
              ),
              field(
                'Confirm Password',
                'password-confirm',
                confirmation,
                (v) =>
                    v != password.text ? 'The passwords do not match.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        AccountingButton.outline(
          context,
          key: const ValueKey('password-cancel'),
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AccountingButton.primary(
          context,
          key: const ValueKey('password-save'),
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
