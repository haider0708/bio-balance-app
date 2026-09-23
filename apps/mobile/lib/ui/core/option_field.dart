import 'package:flutter/material.dart';

import 'design.dart';

/// Searchable choices, with full labels and restoration through the form's
/// controller. No separate selected value can drift away from a saved draft.
class OptionField extends StatefulWidget {
  final String label;
  final Map<String, String> options;
  final TextEditingController controller;
  final bool required, enabled;
  const OptionField({
    super.key,
    required this.label,
    required this.options,
    required this.controller,
    this.required = true,
    this.enabled = true,
  });
  @override
  State<OptionField> createState() => _OptionFieldState();
}

class _OptionFieldState extends State<OptionField> {
  final field = GlobalKey<FormFieldState<String>>();
  String? get selected => widget.options.containsKey(widget.controller.text)
      ? widget.controller.text
      : null;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  @override
  void didUpdateWidget(covariant OptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(changed);
      widget.controller.addListener(changed);
    }
  }

  void changed() {
    field.currentState?.didChange(selected);
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: field,
    initialValue: selected,
    validator: (_) =>
        widget.required && selected == null ? 'Choisissez une valeur.' : null,
    builder: (state) => InkWell(
      onTap: !widget.enabled
          ? null
          : () async {
              FocusScope.of(context).unfocus();
              final value = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _ChoiceSheet(
                  label: widget.label,
                  options: widget.options,
                  selected: selected,
                ),
              );
              if (value != null && mounted) widget.controller.text = value;
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: state.errorText,
          enabled: widget.enabled,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.options[selected] ?? 'Choisir…',
                style: TextStyle(color: widget.enabled ? ink : muted),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(AppIcons.expandMore),
          ],
        ),
      ),
    ),
  );
}

class _ChoiceSheet extends StatefulWidget {
  final String label;
  final Map<String, String> options;
  final String? selected;
  const _ChoiceSheet({
    required this.label,
    required this.options,
    this.selected,
  });
  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final options = widget.options.entries
        .where((entry) => entry.value.toLowerCase().contains(query))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(child: SectionTitle(widget.label)),
            if (widget.options.length > 8)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    onChanged: (value) =>
                        setState(() => query = value.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Rechercher',
                      prefixIcon: Icon(AppIcons.search),
                    ),
                  ),
                ),
              ),
            if (options.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  title: 'Aucun résultat',
                  description: 'Essayez un autre mot.',
                ),
              ),
            SliverList.builder(
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                return CompactRow(
                  title: option.value,
                  selected: option.key == widget.selected,
                  trailing: option.key == widget.selected
                      ? const Icon(
                          AppIcons.check,
                          color: darkGreen,
                          semanticLabel: 'Sélectionné',
                        )
                      : null,
                  onTap: () => Navigator.pop(context, option.key),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
