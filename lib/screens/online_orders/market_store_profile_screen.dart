import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/marketplace/marketplace_store_profile_service.dart';
import '../../utils/app_logger.dart';

/// شاشة تحرير ملف متجر التاجر على Market: الاسم، الوصف، العنوان،
/// الشعار، الغلاف، ومعرض صور المتجر.
class MarketStoreProfileScreen extends StatefulWidget {
  const MarketStoreProfileScreen({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  final String storeId;
  final String storeName;

  @override
  State<MarketStoreProfileScreen> createState() =>
      _MarketStoreProfileScreenState();
}

class _MarketStoreProfileScreenState extends State<MarketStoreProfileScreen> {
  final _service = MarketplaceStoreProfileService();
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _uploadingCover = false;
  bool _uploadingGallery = false;
  String? _error;

  String? _logoUrl;
  String? _coverUrl;
  List<String> _gallery = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await _service.loadStore(widget.storeId);
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = (store?['name'] ?? widget.storeName).toString();
        _descCtrl.text = (store?['description'] ?? '').toString();
        _addressCtrl.text = (store?['pickup_address'] ?? '').toString();
        _logoUrl = store?['logo_url']?.toString();
        _coverUrl = store?['cover_url']?.toString();
        _gallery = ((store?['gallery'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        _loading = false;
      });
    } catch (e) {
      AppLogger.warn('MarketStoreProfile', 'load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<String?> _pickPath() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
    );
    return x?.path;
  }

  Future<void> _changeLogo() async {
    final path = await _pickPath();
    if (path == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final url = await _service.uploadImage(
        storeId: widget.storeId,
        objectName: 'logo.jpg',
        sourcePath: path,
      );
      await _service.setLogo(widget.storeId, url);
      if (!mounted) return;
      setState(() => _logoUrl = url);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _changeCover() async {
    final path = await _pickPath();
    if (path == null) return;
    setState(() => _uploadingCover = true);
    try {
      final url = await _service.uploadImage(
        storeId: widget.storeId,
        objectName: 'cover.jpg',
        sourcePath: path,
      );
      await _service.setCover(widget.storeId, url);
      if (!mounted) return;
      setState(() => _coverUrl = url);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _addGalleryImages() async {
    final files = await _picker.pickMultiImage(maxWidth: 1600);
    if (files.isEmpty) return;
    setState(() => _uploadingGallery = true);
    try {
      final added = <String>[];
      final stamp = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < files.length; i++) {
        final url = await _service.uploadImage(
          storeId: widget.storeId,
          objectName: 'gallery_${stamp}_$i.jpg',
          sourcePath: files[i].path,
        );
        added.add(url);
      }
      final next = [..._gallery, ...added];
      await _service.setGallery(widget.storeId, next);
      if (!mounted) return;
      setState(() => _gallery = next);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _uploadingGallery = false);
    }
  }

  Future<void> _removeGalleryImage(int index) async {
    final next = [..._gallery]..removeAt(index);
    setState(() => _gallery = next);
    try {
      await _service.setGallery(widget.storeId, next);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('اسم المتجر مطلوب');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.updateProfile(
        storeId: widget.storeId,
        name: name,
        description: _descCtrl.text,
        pickupAddress: _addressCtrl.text,
      );
      if (!mounted) return;
      _snack('تم حفظ ملف المتجر');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(Object e) {
    AppLogger.warn('MarketStoreProfile', 'action failed: $e');
    _snack('تعذّرت العملية: $e');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ملف المتجر على Market')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : _form(),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('حفظ التغييرات'),
                ),
              ),
            ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _coverAndLogo(),
        const SizedBox(height: 24),
        TextField(
          controller: _nameCtrl,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'اسم المتجر',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'وصف المتجر',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _addressCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'عنوان المتجر / نقطة الاستلام',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        _gallerySection(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _coverAndLogo() {
    return SizedBox(
      height: 200,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Cover.
          GestureDetector(
            onTap: _uploadingCover ? null : _changeCover,
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF0F2D52),
                image: (_coverUrl != null && _coverUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(_coverUrl!), fit: BoxFit.cover)
                    : null,
              ),
              alignment: AlignmentDirectional.topEnd,
              padding: const EdgeInsets.all(8),
              child: _uploadingCover
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.photo_camera_outlined,
                          color: Colors.white, size: 18),
                    ),
            ),
          ),
          // Logo.
          Positioned(
            bottom: 0,
            child: GestureDetector(
              onTap: _uploadingLogo ? null : _changeLogo,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8),
                  ],
                  image: (_logoUrl != null && _logoUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(_logoUrl!), fit: BoxFit.cover)
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: _uploadingLogo
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_logoUrl == null || _logoUrl!.isEmpty)
                        ? const Icon(Icons.storefront,
                            color: Color(0xFF0F2D52), size: 34)
                        : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gallerySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('صور المتجر',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            TextButton.icon(
              onPressed: _uploadingGallery ? null : _addGalleryImages,
              icon: _uploadingGallery
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('إضافة صور'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_gallery.isEmpty)
          const Text('لا توجد صور بعد',
              style: TextStyle(color: Colors.grey))
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _gallery.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final url = _gallery[index];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 96,
                          height: 96,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: GestureDetector(
                        onTap: () => _removeGalleryImage(index),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
