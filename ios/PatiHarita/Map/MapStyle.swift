/// Sade harita: işletme/ulaşım simgelerini gizler ki yardım işaretleri öne çıksın.
enum MapStyle {
    static let json = """
    [
      { "featureType": "poi.business", "stylers": [{ "visibility": "off" }] },
      { "featureType": "poi", "elementType": "labels.icon", "stylers": [{ "visibility": "off" }] },
      { "featureType": "poi.park", "elementType": "labels.text", "stylers": [{ "visibility": "simplified" }] },
      { "featureType": "transit", "stylers": [{ "visibility": "off" }] },
      { "featureType": "road", "elementType": "labels.icon", "stylers": [{ "visibility": "off" }] }
    ]
    """
}
