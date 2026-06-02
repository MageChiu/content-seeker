import '../../domain/content/content_models.dart';
import 'content_ports.dart';

typedef ContentRendererBuilder = Object Function(ContentEntity entity);

class ContentAdapterDescriptor {
  final String adapterId;
  final String sourceId;
  final String displayName;
  final Set<ContentType> supportedTypes;
  final Set<ContentCapability> capabilities;

  const ContentAdapterDescriptor({
    required this.adapterId,
    required this.sourceId,
    this.displayName = '',
    this.supportedTypes = const {ContentType.unknown},
    this.capabilities = const {},
  });
}

class ContentAdapterBundle {
  final ContentAdapterDescriptor descriptor;
  final ContentSearchPort? searchPort;
  final ContentDetailPort? detailPort;
  final ContentOpenPort? openPort;
  final ContentDownloadPort? downloadPort;
  final ContentSavePort? savePort;
  final ContentLibraryPort? libraryPort;
  final ContentSubscriptionPort? subscriptionPort;

  const ContentAdapterBundle({
    required this.descriptor,
    this.searchPort,
    this.detailPort,
    this.openPort,
    this.downloadPort,
    this.savePort,
    this.libraryPort,
    this.subscriptionPort,
  });

  bool provides(ContentCapability capability) {
    switch (capability) {
      case ContentCapability.search:
        return searchPort != null;
      case ContentCapability.detail:
        return detailPort != null;
      case ContentCapability.open:
        return openPort != null;
      case ContentCapability.download:
        return downloadPort != null;
      case ContentCapability.save:
        return savePort != null;
      case ContentCapability.library:
        return libraryPort != null;
      case ContentCapability.subscribe:
        return subscriptionPort != null;
    }
  }
}

class ContentRendererDescriptor {
  final String rendererId;
  final String displayName;
  final Set<ContentType> supportedTypes;
  final Set<ContentEntityKind> supportedKinds;

  const ContentRendererDescriptor({
    required this.rendererId,
    this.displayName = '',
    this.supportedTypes = const {ContentType.unknown},
    this.supportedKinds = const {ContentEntityKind.item},
  });
}

class ContentRendererRegistration {
  final ContentRendererDescriptor descriptor;
  final ContentRendererBuilder builder;

  const ContentRendererRegistration({
    required this.descriptor,
    required this.builder,
  });
}

class ContentAdapterRegistry {
  final Map<String, ContentAdapterBundle> _bundlesByAdapterId;

  ContentAdapterRegistry._(this._bundlesByAdapterId);

  factory ContentAdapterRegistry({
    Iterable<ContentAdapterBundle> bundles = const [],
  }) {
    final mapped = <String, ContentAdapterBundle>{};
    for (final bundle in bundles) {
      mapped[bundle.descriptor.adapterId] = bundle;
    }
    return ContentAdapterRegistry._(Map.unmodifiable(mapped));
  }

  Iterable<ContentAdapterBundle> get bundles => _bundlesByAdapterId.values;

  ContentAdapterBundle? findByAdapterId(String adapterId) {
    return _bundlesByAdapterId[adapterId];
  }

  Iterable<ContentAdapterBundle> findBySourceId(String sourceId) {
    return bundles.where((bundle) => bundle.descriptor.sourceId == sourceId);
  }

  Iterable<ContentAdapterBundle> findByCapability(ContentCapability capability) {
    return bundles.where((bundle) => bundle.provides(capability));
  }
}

class ContentRendererRegistry {
  final Map<String, ContentRendererRegistration> _renderersById;

  ContentRendererRegistry._(this._renderersById);

  factory ContentRendererRegistry({
    Iterable<ContentRendererRegistration> renderers = const [],
  }) {
    final mapped = <String, ContentRendererRegistration>{};
    for (final renderer in renderers) {
      mapped[renderer.descriptor.rendererId] = renderer;
    }
    return ContentRendererRegistry._(Map.unmodifiable(mapped));
  }

  Iterable<ContentRendererRegistration> get renderers => _renderersById.values;

  ContentRendererRegistration? findById(String rendererId) {
    return _renderersById[rendererId];
  }

  Iterable<ContentRendererRegistration> match(ContentEntity entity) {
    return renderers.where((renderer) {
      return renderer.descriptor.supportedTypes.contains(entity.handle.type) &&
          renderer.descriptor.supportedKinds.contains(entity.handle.kind);
    });
  }
}
