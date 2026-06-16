import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/widgets/image_preview.dart';
import 'package:nousmind/widgets/image_preview_screen.dart';

/// Outcome of attempting to pick an image, used internally by the editor.
enum _PickOutcome { selected, cancelled, failed }

class _PickResult {
  const _PickResult(this.outcome, [this.file]);

  final _PickOutcome outcome;
  final XFile? file;
}

/// Add/edit form for a single [Inspiration]. Pops a tuple of the resulting
/// [Inspiration] and the previously-stored image path (when replacing an
/// existing image) so the caller can clean up stale files.
class InspirationEditorPage extends StatefulWidget {
  const InspirationEditorPage({super.key, this.initial});

  /// Existing inspiration when editing, null when adding a new one.
  final Inspiration? initial;

  @override
  State<InspirationEditorPage> createState() => _InspirationEditorPageState();
}

class _InspirationEditorPageState extends State<InspirationEditorPage> {
  static const String _textRequiredError = '请输入内容';

  final TextEditingController _textController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  bool _picking = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _textController.text = initial.text;
      _imagePath = initial.imagePath;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_picking) {
      return;
    }
    setState(() => _picking = true);
    final result = await _pick(source);
    if (!mounted) {
      return;
    }
    setState(() => _picking = false);
    switch (result.outcome) {
      case _PickOutcome.cancelled:
        break;
      case _PickOutcome.selected:
        setState(() => _imagePath = result.file!.path);
      case _PickOutcome.failed:
        context.showAppSnackBar('获取图片失败');
    }
  }

  Future<_PickResult> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      return _PickResult(
        file == null ? _PickOutcome.cancelled : _PickOutcome.selected,
        file,
      );
    } on PlatformException catch (error, stackTrace) {
      developer.log('Image pick failed', error: error, stackTrace: stackTrace);
      return const _PickResult(_PickOutcome.failed);
    }
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final viewModel = context.read<InspirationsViewModel>();
    final store = context.read<InspirationImageStore>();
    final text = _textController.text.trim();
    final existing = widget.initial;
    final previousImagePath = existing?.imagePath;
    String? newImagePath = _imagePath;

    // If the user picked a new image, copy it into the managed directory.
    if (newImagePath != null && newImagePath != previousImagePath) {
      final inspirationId =
          existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
      final source = XFile(newImagePath);
      newImagePath = await store.save(
        inspirationId: inspirationId,
        source: source,
      );
    }

    if (existing == null) {
      await viewModel.add(text: text, imagePath: newImagePath);
    } else {
      await viewModel.update(
        existing.copyWith(text: text, imagePath: newImagePath),
      );
      // If the image was replaced or cleared, delete the stale file.
      if (previousImagePath != null && previousImagePath != newImagePath) {
        await store.deleteByPath(previousImagePath);
      }
    }

    if (!mounted) {
      return;
    }
    context.pop();
  }

  void _removeImage() {
    setState(() => _imagePath = null);
  }

  /// Hero tag for the editor's image. Uses the persisted id when
  /// editing, otherwise fingerprints the current path so the tag
  /// changes if the user picks a new image.
  String _imageHeroTag() {
    final id = widget.initial?.id;
    return id != null
        ? 'editor-image:$id'
        : 'editor-image:new-${_imagePath.hashCode}';
  }

  void _openImagePreview() {
    if (_imagePath == null) return;
    Navigator.of(context, rootNavigator: true).push(
      openImagePreviewRoute(
        imagePath: _imagePath!,
        heroTag: _imageHeroTag(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑灵感' : '新增灵感'),
        actions: <Widget>[
          TextButton(
            onPressed: _picking ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              ImagePreview(
                imagePath: _imagePath,
                onRemove: _imagePath == null ? null : _removeImage,
                onTap: _imagePath == null ? null : _openImagePreview,
                heroTag: _imagePath == null ? null : _imageHeroTag(),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _picking
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('相册'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _picking
                          ? null
                          : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('拍照'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _textController,
                minLines: 4,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: '内容',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _textRequiredError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_picking)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(color: colors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
