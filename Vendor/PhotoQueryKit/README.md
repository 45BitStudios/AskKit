# PhotoQueryKit

A Swift package for querying, filtering, and indexing the iOS/macOS photo library. Designed to be driven by foundation models / tool calling (“get all my images wider than 2000 px from June 2024”).

## Features

- Structured `PhotoQueryRequest` (Codable) for LLM tool calling
- Pixel-size, date-range, media-type, subtype, favorite, album, and location filters
- Vision indexing (classification labels + OCR + optional feature prints)
- Thumbnail caching via `PHCachingImageManager`
- Simple natural-language fallback parser
- Cloud-identifier ready

## Installation

Add to your `Package.swift` or Xcode:

```swift
.package(url: "path/to/PhotoQueryKit", from: "1.0.0")
```

Host app **Info.plist**:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Access your photo library to search and filter images.</string>
```

## Basic Usage

```swift
import PhotoQueryKit

let query = PhotoQuery.shared

// 1. Authorize
guard await query.ensureAuthorized() else { return }

// 2. Structured request (ideal for foundation models)
var request = PhotoQueryRequest()
request.mediaType = .image
request.minWidth = 2000
request.startDate = Date().addingTimeInterval(-30 * 24 * 3600)
request.isFavorite = true
request.limit = 50

let results = await query.query(request)

// 3. Natural language (fallback)
let more = await query.query(naturalLanguage: "screenshots from last month wider than 1000px")
```

## Foundation Model / Tool Calling

Expose this tool schema to your model:

```json
{
  "name": "query_photos",
  "description": "Query the user's photo library with structured filters",
  "parameters": {
    "type": "object",
    "properties": {
      "mediaType": { "type": "string", "enum": ["image", "video", "livePhoto", "any"] },
      "minWidth": { "type": "integer" },
      "maxWidth": { "type": "integer" },
      "minHeight": { "type": "integer" },
      "maxHeight": { "type": "integer" },
      "startDate": { "type": "string", "format": "date-time" },
      "endDate": { "type": "string", "format": "date-time" },
      "isFavorite": { "type": "boolean" },
      "mediaSubtypes": { "type": "array", "items": { "type": "string" } },
      "albumTitle": { "type": "string" },
      "textSearch": { "type": "string" },
      "limit": { "type": "integer" }
    }
  }
}
```

When the model emits a `PhotoQueryRequest` JSON, decode it and call:

```swift
let request = try JSONDecoder().decode(PhotoQueryRequest.self, from: jsonData)
let results = await PhotoQuery.shared.query(request)
```

## Vision Indexing

The Vision index is persisted on disk under Application Support (`PhotoQueryKit/vision-index.json`), including `lastIndexedAt`. It is not synced with CloudKit.

```swift
// App launch: reload the saved index, then index only photos newer than lastIndexedAt.
await PhotoQuery.shared.prepareIndexOnLaunch(limit: 300) { progress in
    print("\(progress.completed)/\(progress.total) · \(progress.indexedCount) stored")
}

let last = await PhotoQuery.shared.lastIndexDate()
_ = await PhotoQuery.shared.saveIndex()

// Later: find photos whose Vision labels or OCR contain “dog” or “receipt”
let ids = await PhotoQuery.shared.visionSearch(query: "dog")
let count = await PhotoQuery.shared.indexedCount()

// Visually similar photos (needs feature prints from indexing)
var similar = PhotoQueryRequest()
similar.similarToLocalIdentifier = "LOCAL_ID"
similar.limit = 12
let neighbors = await PhotoQuery.shared.query(similar)
```

## Caching

```swift
let cache = PhotoQuery.shared.cache
// After you have a list of PHAssets
cache.startCaching(assets: assets, targetSize: CGSize(width: 200, height: 200))
let thumb = await cache.requestThumbnail(for: asset)
```

## Notes

- Predicate keys supported by PhotoKit are limited (`pixelWidth`, `pixelHeight`, `creationDate`, `mediaType`, `mediaSubtypes`, `isFavorite`, etc.). Location and free-text are applied after the fetch.
- Vision indexing is on-device and respects the user’s library; run it incrementally.
- Prefer structured `PhotoQueryRequest` over the simple natural-language parser for production foundation-model work.
- For cross-device persistence, map `localIdentifier` ↔ `PHCloudIdentifier` via `PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers:)`.

## License

MIT
