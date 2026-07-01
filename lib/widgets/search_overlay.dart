import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:safer_chat/generated/app_localizations.dart';
import '../models/search_result.dart';
import '../services/search_service.dart';
import '../theme.dart';
import '../providers/font_scale_provider.dart';
import '../utils/platform_utils.dart';

class SearchOverlay extends StatefulWidget {
  final String token;
  final String baseUrl;
  final int myUserId;
  final Function(SearchResult) onResultTap;
  final VoidCallback onClose;
  final TextEditingController searchController;

  const SearchOverlay({
    Key? key,
    required this.token,
    required this.baseUrl,
    required this.myUserId,
    required this.onResultTap,
    required this.onClose,
    required this.searchController,
  }) : super(key: key);

  @override
  SearchOverlayState createState() => SearchOverlayState();
}

class SearchOverlayState extends State<SearchOverlay> {
  late SearchService _searchService;
  List<SearchResult> _searchResults = [];
  List<SearchResult> _recentSearches = [];
  bool _isLoading = false;
  bool _showRecent = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchService = SearchService(
      baseUrl: widget.baseUrl,
      token: widget.token,
    );
    _loadRecentSearches();
    widget.searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.searchController.removeListener(_onSearchChanged);
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final recent = await _searchService.getRecentSearches();
    if (mounted) {
      setState(() {
        _recentSearches = recent;
      });
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (widget.searchController.text.isEmpty) {
      setState(() {
        _showRecent = true;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _showRecent = false;
      _isLoading = true;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    final results = await _searchService.searchAll(widget.searchController.text);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  void _handleResultTap(SearchResult result) async {
    await _searchService.saveRecentSearch(result);
    widget.onResultTap(result);
    widget.onClose();
  }

  IconData _getIconForType(SearchResultType type) {
    switch (type) {
      case SearchResultType.chat:
        return Icons.chat_bubble_outline;
      case SearchResultType.contact:
        return Icons.person_outline;
      case SearchResultType.channel:
        return Icons.campaign;
      case SearchResultType.group:
        return Icons.group;
    }
  }

  String _getTypeLabel(SearchResultType type, BuildContext context) {
    switch (type) {
      case SearchResultType.chat:
        return AppLocalizations.of(context)!.chats;
      case SearchResultType.contact:
        return AppLocalizations.of(context)!.contacts;
      case SearchResultType.channel:
        return AppLocalizations.of(context)!.channels;
      case SearchResultType.group:
        return AppLocalizations.of(context)!.groups;
    }
  }

  Widget _buildRecentSearches() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    if (_recentSearches.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32 * fontSizeScale),
          child: Text(
            AppLocalizations.of(context)!.searchInChatsContactsChannels,
            style: TextStyle(
              fontSize: MessengerTheme.fontSizeLG * fontSizeScale,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: EdgeInsets.all(16 * fontSizeScale),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.recentSearches,
                style: TextStyle(
                  fontSize: MessengerTheme.fontSizeLG * fontSizeScale,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await _searchService.clearRecentSearches();
                  setState(() {
                    _recentSearches = [];
                  });
                },
                child: Text(
                  AppLocalizations.of(context)!.clearRecentSearches,
                  style: TextStyle(
                    fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
                    color: MessengerTheme.lightAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._recentSearches.map((result) => _buildResultItem(result, isRecent: true)),
      ],
    );
  }

  Widget _buildSearchResults() {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    if (_isLoading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32 * fontSizeScale),
          child: CircularProgressIndicator(
            color: MessengerTheme.lightAccent,
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32 * fontSizeScale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 64 * fontSizeScale,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
              SizedBox(height: 16 * fontSizeScale),
              Text(
                AppLocalizations.of(context)!.nothingFound,
                style: TextStyle(
                  fontSize: MessengerTheme.fontSizeXL * fontSizeScale,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final chats = _searchResults.where((r) => r.type == SearchResultType.chat).toList();
    final contacts = _searchResults.where((r) => r.type == SearchResultType.contact).toList();
    final channels = _searchResults.where((r) => r.type == SearchResultType.channel).toList();
    final groups = _searchResults.where((r) => r.type == SearchResultType.group).toList();

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        if (chats.isNotEmpty) ...[
          _buildSectionHeader(AppLocalizations.of(context)!.chats),
          ...chats.map((result) => _buildResultItem(result)),
        ],
        if (contacts.isNotEmpty) ...[
          _buildSectionHeader(AppLocalizations.of(context)!.contacts),
          ...contacts.map((result) => _buildResultItem(result)),
        ],
        if (channels.isNotEmpty) ...[
          _buildSectionHeader(AppLocalizations.of(context)!.channels),
          ...channels.map((result) => _buildResultItem(result)),
        ],
        if (groups.isNotEmpty) ...[
          _buildSectionHeader(AppLocalizations.of(context)!.groups),
          ...groups.map((result) => _buildResultItem(result)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 * fontSizeScale,
        16 * fontSizeScale,
        16 * fontSizeScale,
        8 * fontSizeScale,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: MessengerTheme.fontSizeLG * fontSizeScale,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
        ),
      ),
    );
  }

  Widget _buildResultItem(SearchResult result, {bool isRecent = false}) {
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    return InkWell(
      onTap: () => _handleResultTap(result),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * fontSizeScale,
          vertical: 12 * fontSizeScale,
        ),
        child: Row(
          children: [
            Container(
              width: 48 * fontSizeScale,
              height: 48 * fontSizeScale,
              decoration: BoxDecoration(
                gradient: MessengerTheme.getAvatarGradient(result.id),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIconForType(result.type),
                color: Colors.white,
                size: 24 * fontSizeScale,
              ),
            ),
            SizedBox(width: 12 * fontSizeScale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: TextStyle(
                      fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.subtitle != null) ...[
                    SizedBox(height: 4 * fontSizeScale),
                    Text(
                      result.subtitle!,
                      style: TextStyle(
                        fontSize: MessengerTheme.fontSizeSM * fontSizeScale,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Text(
              _getTypeLabel(result.type, context),
              style: TextStyle(
                fontSize: MessengerTheme.fontSizeSM * fontSizeScale,
                color: MessengerTheme.lightAccent.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    if (isMobile) {
      // Для мобильных - полноэкранное модальное окно
      return Material(
        type: MaterialType.transparency,
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              // Верхняя панель с кнопкой назад
              Container(
                padding: EdgeInsets.all(16 * fontSizeScale),
                decoration: BoxDecoration(
                  color: MessengerTheme.lightAccent,
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: widget.onClose,
                        color: Colors.white,
                      ),
                      Expanded(
                        child: TextField(
                          controller: widget.searchController,
                          autofocus: true,
                          style: TextStyle(
                            fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)!.searchInChatsContactsChannels,
                            hintStyle: TextStyle(
                              fontSize: MessengerTheme.fontSizeBase * fontSizeScale,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (widget.searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            widget.searchController.clear();
                          },
                          color: Colors.white,
                        ),
                    ],
                  ),
                ),
              ),
              // Список результатов
              Expanded(
                child: _showRecent ? _buildRecentSearches() : _buildSearchResults(),
              ),
            ],
          ),
        ),
      );
    }

    // Для веба - выпадающий список под поиском
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Прозрачный фон для закрытия
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          // Выпадающий список
          Positioned(
            top: 80 * fontSizeScale,
            left: 20 * fontSizeScale,
            right: 20 * fontSizeScale,
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 600 * fontSizeScale,
                  maxHeight: 500 * fontSizeScale,
                ),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(MessengerTheme.radiusXL * fontSizeScale),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(MessengerTheme.radiusXL * fontSizeScale),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(MessengerTheme.radiusXL * fontSizeScale),
                      child: _showRecent ? _buildRecentSearches() : _buildSearchResults(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}