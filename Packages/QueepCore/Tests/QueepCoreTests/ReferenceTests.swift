import Testing
import Foundation
@testable import QueepCore

@Test func captureValidationPreventsUnsafeLinksAndEmptyNotes() {
    #expect(!Capture(kind: "note", title: "", text: "  \n ").isValid)
    #expect(!Capture(kind: "link", title: "", text: "", url: "javascript:alert(1)").isValid)
    #expect(!Capture(kind: "link", title: "", text: "", url: "https://u:secret@example.com").isValid)
    #expect(Capture(kind: "link", title: "", text: "", url: "https://github.com").isValid)
    #expect(Capture(kind: "note", title: "", text: "CRM com fundo branco").isValid)
    #expect(!Capture(kind: "note", title: "", text: String(repeating: "a", count: 30_001)).isValid)
}

@Test func decodesBackendDatesAndPartialAnalysis() throws {
    let json = #"{"items":[{"id":"123","kind":"link","title":"","text":"","url":"https://github.com","status":"ready","revision":2,"created_at":"2026-09-10T15:00:00.123456+00:00","updated_at":"2026-09-10T15:00:00Z","analysis":{"summary":"Repository","topics":[],"entities":[],"usefulness":[],"appearance":[],"coverage":"partial","limitations":["Only title available"]}}],"next_cursor":"cursor"}"#
    let page = try APIClient.decoder().decode(LibraryPage.self, from: Data(json.utf8))
    #expect(page.items.count == 1)
    #expect(page.nextCursor == "cursor")
    #expect(page.items[0].displayTitle == "github.com")
    #expect(page.items[0].statusLabel == "Análise parcial")
    #expect(page.items[0].analysis?.limitations == ["Only title available"])
    #expect(page.items[0].source == nil)
    #expect(!page.items[0].isArchived)
}

@Test func decodesArchivedState() throws {
    let raw = #"{"id":"archived","kind":"note","title":"Guardada","text":"Texto","url":null,"status":"ready","revision":1,"created_at":"2026-09-20T15:00:00Z","updated_at":"2026-09-20T16:00:00Z","archived_at":"2026-09-20T16:00:00Z"}"#
    let reference = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(reference.isArchived)
    #expect(reference.archivedAt != nil)
}

@Test func identifiesSocialPostsSeparatelyFromGenericSites() {
    #expect(LinkSurface.identify(url: "https://x.com/someone/status/1") == .twitter)
    #expect(LinkSurface.identify(url: "https://twitter.com/someone/status/1") == .twitter)
    #expect(LinkSurface.identify(url: "https://www.instagram.com/p/example/") == .instagram)
    #expect(LinkSurface.identify(url: "https://dribbble.com/shots/123") == .dribbble)
    #expect(LinkSurface.identify(url: "https://www.behance.net/gallery/1") == .behance)
    #expect(LinkSurface.identify(url: "https://www.pinterest.com/pin/545287467382811935/") == .pinterest)
    #expect(LinkSurface.identify(url: "https://medium.com/@author/article") == .medium)
    #expect(LinkSurface.identify(url: "https://cursor.com") == .website)
    #expect(LinkSurface.identify(url: "https://x.com/someone/status/1").isPost)
    #expect(!LinkSurface.identify(url: "https://cursor.com").isPost)
    #expect(LinkSurface.twitterHandle(url: "https://x.com/richardrx/status/2099853605054316775") == "richardrx")
    #expect(LinkSurface.twitterHandle(url: "https://x.com/i/web/status/2099853605054316775") == nil)
    #expect(LinkSurface.twitterProfileHandle(url: "https://x.com/ada") == "ada")
    #expect(LinkSurface.twitterProfileHandle(url: "https://twitter.com/Ada_123/") == "Ada_123")
    #expect(LinkSurface.twitterProfileHandle(url: "https://x.com/ada/status/1") == nil)
    #expect(LinkSurface.twitterProfileHandle(url: "https://x.com/search") == nil)
    #expect(LinkSurface.twitterProfileHandle(url: "https://x.com/hashtag/design") == nil)
    #expect(LinkSurface.twitterProfileHandle(url: "https://x.com/intent/user") == nil)
    #expect(LinkSurface.twitterProfileHandle(url: "https://x.com/i/web") == nil)
    #expect(LinkSurface.instagramPostCode(url: "https://www.instagram.com/p/AbC_12/") == "AbC_12")
    #expect(LinkSurface.instagramPostCode(url: "https://www.instagram.com/reel/AbC_12/") == "AbC_12")
    #expect(LinkSurface.instagramPostCode(url: "https://www.instagram.com/ada/reel/AbC_12/") == "AbC_12")
    #expect(LinkSurface.instagramPostCode(url: "https://www.instagram.com/share/reel/AbC_12/") == "AbC_12")
    #expect(LinkSurface.instagramProfileHandle(url: "https://www.instagram.com/ada.lovelace/") == "ada.lovelace")
    #expect(LinkSurface.instagramProfileHandle(url: "https://www.instagram.com/p/AbC_12/") == nil)
    #expect(LinkSurface.instagramProfileHandle(url: "https://www.instagram.com/stories/ada") == nil)
    #expect(LinkSurface.dribbbleShot(url: "https://dribbble.com/shots/123") == "123")
    #expect(LinkSurface.behanceProjectId(url: "https://www.behance.net/gallery/210524379/Reel-2024") == "210524379")
}

@Test func classifiesDribbbleShotSeparatelyFromDesignerProfile() throws {
    #expect(LinkSurface.dribbbleShot(url: "https://dribbble.com/shots/27064263-Hero-Screen") == "27064263")
    #expect(LinkSurface.dribbbleShot(url: "https://dribbble.com/ada") == nil)
    #expect(LinkSurface.dribbbleProfileHandle(url: "https://dribbble.com/ada-design") == "ada-design")
    #expect(LinkSurface.dribbbleProfileHandle(url: "https://dribbble.com/shots/123-Title") == nil)
    #expect(LinkSurface.dribbbleProfileHandle(url: "https://dribbble.com/designers") == nil)
    #expect(LinkSurface.dribbbleProfileHandle(url: "https://dribbble.com/search") == nil)
    #expect(LinkSurface.dribbbleProfileHandle(url: "https://dribbble.com/signup") == nil)
    #expect(LinkSurface.dribbbleProfileHandle(url: "https://dribbble.com/session") == nil)
    #expect(LinkSurface.dribbbleProfileHandle(url: "https://dribbble.com/jobs") == nil)
    #expect(LinkSurface.dribbbleShot(url: "https://dribbble.com.example.org/shots/123") == nil)

    let shotRaw = #"{"id":"d","kind":"link","title":"Shot","text":"","url":"https://dribbble.com/shots/123-Title","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let shot = try APIClient.decoder().decode(Reference.self, from: Data(shotRaw.utf8))
    #expect(shot.isSocialPost)
    #expect(!shot.isSocialProfile)
    #expect(!shot.isWebsite)

    let profileRaw = #"{"id":"p","kind":"link","title":"","text":"","url":"https://dribbble.com/ada-design","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let profile = try APIClient.decoder().decode(Reference.self, from: Data(profileRaw.utf8))
    #expect(profile.isSocialProfile)
    #expect(!profile.isSocialPost)
    #expect(!profile.isWebsite)
}

@Test func classifiesBehanceProjectSeparatelyFromDesignerProfile() throws {
    #expect(LinkSurface.behanceProjectId(url: "https://www.behance.net/gallery/123/Title") == "123")
    #expect(LinkSurface.behanceProjectId(url: "https://behance.net/gallery/123/Title/modules/9") == "123")
    #expect(LinkSurface.behanceProjectId(url: "https://www.behance.net/ada") == nil)
    #expect(LinkSurface.behanceProfileHandle(url: "https://www.behance.net/ada-design") == "ada-design")
    #expect(LinkSurface.behanceProfileHandle(url: "https://be.net/Ada_Design/") == "Ada_Design")
    #expect(LinkSurface.behanceProfileHandle(url: "https://www.behance.net/gallery/123/Title") == nil)
    #expect(LinkSurface.behanceProfileHandle(url: "https://www.behance.net/galleries") == nil)
    #expect(LinkSurface.behanceProfileHandle(url: "https://www.behance.net/search") == nil)
    #expect(LinkSurface.behanceProfileHandle(url: "https://www.behance.net/hire") == nil)
    #expect(LinkSurface.behanceProfileHandle(url: "https://www.behance.net/joblist") == nil)
    #expect(LinkSurface.behanceProfileHandle(url: "https://www.behance.net/ada/services/1") == nil)
    #expect(LinkSurface.behanceProjectId(url: "https://behance.net.example.org/gallery/123") == nil)

    let projectRaw = #"{"id":"b","kind":"link","title":"Mixer","text":"","url":"https://www.behance.net/gallery/123/Title","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let project = try APIClient.decoder().decode(Reference.self, from: Data(projectRaw.utf8))
    #expect(project.isSocialPost)
    #expect(!project.isSocialProfile)
    #expect(!project.isWebsite)
    #expect(project.kindLabel == "Post")

    let profileRaw = #"{"id":"p","kind":"link","title":"","text":"","url":"https://www.behance.net/ada-design","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let profile = try APIClient.decoder().decode(Reference.self, from: Data(profileRaw.utf8))
    #expect(profile.isSocialProfile)
    #expect(!profile.isSocialPost)
    #expect(!profile.isWebsite)
    #expect(profile.kindLabel == "Perfil")
}

@Test func classifiesPinterestPinSeparatelyFromCreatorProfile() throws {
    #expect(LinkSurface.pinterestPinId(
        url: "https://www.pinterest.com/pin/545287467382811935/"
    ) == "545287467382811935")
    #expect(LinkSurface.pinterestPinId(
        url: "https://br.pinterest.com/pin/design--545287467382811935/"
    ) == "545287467382811935")
    #expect(LinkSurface.pinterestPinId(url: "https://pin.it/4Ab_Cd9") == "4Ab_Cd9")
    #expect(LinkSurface.pinterestProfileHandle(
        url: "https://www.pinterest.com/ada_design/"
    ) == "ada_design")
    #expect(LinkSurface.pinterestProfileHandle(url: "https://www.pinterest.com/search/") == nil)
    #expect(LinkSurface.pinterestProfileHandle(url: "https://www.pinterest.com/123456/") == nil)
    #expect(LinkSurface.pinterestProfileHandle(
        url: "https://www.pinterest.com/ada_design/boards/"
    ) == nil)
    #expect(LinkSurface.pinterestPinId(
        url: "https://pinterest.com.example.org/pin/545287467382811935/"
    ) == nil)

    let pinRaw = #"{"id":"pin","kind":"link","title":"Idea","text":"","url":"https://www.pinterest.com/pin/545287467382811935/","status":"ready","revision":1,"created_at":"2026-09-19T15:00:00Z","updated_at":"2026-09-19T15:00:00Z"}"#
    let pin = try APIClient.decoder().decode(Reference.self, from: Data(pinRaw.utf8))
    #expect(pin.isSocialPost)
    #expect(!pin.isSocialProfile)
    #expect(!pin.isWebsite)
    #expect(pin.kindLabel == "Post")

    let profileRaw = #"{"id":"profile","kind":"link","title":"","text":"","url":"https://www.pinterest.com/ada_design/","status":"ready","revision":1,"created_at":"2026-09-19T15:00:00Z","updated_at":"2026-09-19T15:00:00Z"}"#
    let profile = try APIClient.decoder().decode(Reference.self, from: Data(profileRaw.utf8))
    #expect(profile.isSocialProfile)
    #expect(!profile.isSocialPost)
    #expect(!profile.isWebsite)
    #expect(profile.kindLabel == "Perfil")
    #expect(profile.displayTitle == "ada_design")
}

@Test func classifiesTwitterProfileSeparatelyFromPost() throws {
    let profileRaw = #"{"id":"p","kind":"link","title":"","text":"","url":"https://x.com/ada","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z","source":{"state":"read","url":"https://x.com/ada","title":"Ada Lovelace","text":"Bio curta.","author_name":"Ada Lovelace","author_handle":"ada","native_title":true,"fetched_at":"2026-09-17T15:00:00Z","truncated":false,"limitations":[]}}"#
    let profile = try APIClient.decoder().decode(Reference.self, from: Data(profileRaw.utf8))
    #expect(profile.isSocialProfile)
    #expect(!profile.isSocialPost)
    #expect(profile.kindLabel == "Perfil")
    #expect(profile.displayTitle == "Ada Lovelace")

    let postRaw = #"{"id":"t","kind":"link","title":"Mixer","text":"","url":"https://x.com/ada/status/1","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let post = try APIClient.decoder().decode(Reference.self, from: Data(postRaw.utf8))
    #expect(post.isSocialPost)
    #expect(!post.isSocialProfile)
    #expect(post.kindLabel == "Post")
}

@Test func classifiesInstagramPostSeparatelyFromProfile() throws {
    let profileRaw = #"{"id":"p","kind":"link","title":"","text":"","url":"https://www.instagram.com/ada.lovelace","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z","source":{"state":"read","url":"https://www.instagram.com/ada.lovelace","title":"Ada Lovelace","text":"Bio.","author_name":"Ada Lovelace","author_handle":"ada.lovelace","native_title":true,"fetched_at":"2026-09-17T15:00:00Z","truncated":false,"limitations":[]}}"#
    let profile = try APIClient.decoder().decode(Reference.self, from: Data(profileRaw.utf8))
    #expect(profile.isSocialProfile)
    #expect(!profile.isSocialPost)
    #expect(!profile.isWebsite)
    #expect(profile.kindLabel == "Perfil")

    let postRaw = #"{"id":"t","kind":"link","title":"Mixer","text":"","url":"https://www.instagram.com/p/AbC_12/","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let post = try APIClient.decoder().decode(Reference.self, from: Data(postRaw.utf8))
    #expect(post.isSocialPost)
    #expect(!post.isSocialProfile)
    #expect(post.kindLabel == "Post")
}

@Test func classifiesWebsiteSeparatelyFromYoutubeAndMedium() throws {
    let siteRaw = #"{"id":"s","kind":"link","title":"Editor de codigo com agentes","text":"","url":"https://cursor.com","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z","source":{"state":"read","url":"https://cursor.com","title":"Cursor","text":"Editor.","native_title":false,"fetched_at":"2026-09-17T15:00:00Z","truncated":false,"limitations":[]}}"#
    let site = try APIClient.decoder().decode(Reference.self, from: Data(siteRaw.utf8))
    #expect(site.isWebsite)
    #expect(!site.isSocialPost)
    #expect(site.kindLabel == "Site")
    #expect(site.displayTitle == "Editor de codigo com agentes")

    let youtubeRaw = #"{"id":"y","kind":"link","title":"Official video","text":"","url":"https://youtu.be/dQw4w9WgXcQ","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let youtube = try APIClient.decoder().decode(Reference.self, from: Data(youtubeRaw.utf8))
    #expect(!youtube.isWebsite)
    #expect(LinkSurface.isVideoPage(youtube.url))
    #expect(youtube.kindLabel == "Link")

    let mediumRaw = #"{"id":"m","kind":"link","title":"Essay","text":"","url":"https://medium.com/@author/article","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let medium = try APIClient.decoder().decode(Reference.self, from: Data(mediumRaw.utf8))
    #expect(!medium.isWebsite)
    #expect(medium.linkSurface == .medium)

    let exploreRaw = #"{"id":"e","kind":"link","title":"","text":"","url":"https://www.instagram.com/explore/","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let explore = try APIClient.decoder().decode(Reference.self, from: Data(exploreRaw.utf8))
    #expect(explore.linkSurface == .instagram)
    #expect(!explore.isWebsite)
    #expect(!explore.isSocialPost)
    #expect(explore.kindLabel == "Link")

    let listingRaw = #"{"id":"d","kind":"link","title":"","text":"","url":"https://dribbble.com/shots","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z"}"#
    let listing = try APIClient.decoder().decode(Reference.self, from: Data(listingRaw.utf8))
    #expect(listing.linkSurface == .dribbble)
    #expect(!listing.isWebsite)
    #expect(listing.kindLabel == "Link")
}

@Test func postPlaceholderDoesNotReplaceAuthorHandle() throws {
    let raw = #"{"id":"post","kind":"link","title":"","text":"","url":"https://x.com/yurygok/status/1","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z","source":{"state":"read","url":"https://x.com/yurygok/status/1","title":"Post","text":"","fetched_at":"2026-09-17T15:00:00Z","truncated":false,"limitations":[]}}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.displayTitle == "yurygok")
    #expect(ref.source?.title == "Post")
}

@Test func decodesExtractedSourceWithoutReplacingUserTitleOrContext() throws {
    let raw = #"{"id":"link","kind":"link","title":"","text":"Meu contexto","url":"https://example.com","status":"ready","revision":1,"created_at":"2026-09-11T15:00:00Z","updated_at":"2026-09-11T15:00:00Z","source":{"state":"read","url":"https://example.com/page","title":"Título da página","text":"Conteúdo extraído","fetched_at":"2026-09-11T15:00:00Z","truncated":true,"limitations":["Trecho"]}}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.source?.text == "Conteúdo extraído")
    #expect(ref.source?.truncated == true)
    #expect(ref.displayTitle == "Título da página")
    #expect(ref.title.isEmpty && ref.text == "Meu contexto")
    let titled = raw.replacingOccurrences(of: #""title":"""#, with: #""title":"Minha referência""#)
    let custom = try APIClient.decoder().decode(Reference.self, from: Data(titled.utf8))
    #expect(custom.displayTitle == "Minha referência")
}

@Test func decodesFourPhotoPostGallery() throws {
    let raw = #"{"id":"post","kind":"link","title":"Post","text":"","url":"https://x.com/a/status/1","status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","image":{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12},"images":[{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12},{"sha256":"bb","content_type":"image/jpeg","width":800,"height":600,"byte_count":10},{"sha256":"cc","content_type":"image/jpeg","width":700,"height":600,"byte_count":9},{"sha256":"dd","content_type":"image/jpeg","width":600,"height":600,"byte_count":8}]}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.gallery.count == 4)
}

@Test func decodesPostGalleryWithoutDroppingThePrimaryImage() throws {
    let raw = #"{"id":"post","kind":"link","title":"Post","text":"","url":"https://x.com/a/status/1","status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","image":{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12},"images":[{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12},{"sha256":"bb","content_type":"image/jpeg","width":800,"height":600,"byte_count":10}]}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.gallery.count == 2)
    #expect(ref.gallery[1].sha256 == "bb")
    #expect(ref.image?.sha256 == "aa")
}

@Test func decodesVideoPosterPreviewKind() throws {
    let raw = #"{"id":"post","kind":"link","title":"Cena do clipe","text":"","url":"https://x.com/a/status/1","status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","image":{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12,"preview_kind":"video"},"images":[{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12,"preview_kind":"video"},{"sha256":"bb","content_type":"image/jpeg","width":800,"height":600,"byte_count":10}]}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.gallery[0].isVideoPreview)
    #expect(ref.gallery[1].isVideoPreview == false)
    #expect(ref.gallery[0].motion != true)
}

@Test func inlineLoopFollowsMotionAndUploadedLoop() throws {
    let gif = try APIClient.decoder().decode(Reference.self, from: Data(#"{"id":"g","kind":"link","title":"Loop","text":"","url":"https://x.com/a/status/1","status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","images":[{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12,"preview_kind":"gif","motion":true}]}"#.utf8))
    #expect(gif.playsInlineLoop)

    let stillGif = try APIClient.decoder().decode(Reference.self, from: Data(#"{"id":"s","kind":"link","title":"Still","text":"","url":"https://x.com/a/status/1","status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","images":[{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12,"preview_kind":"gif"}]}"#.utf8))
    #expect(stillGif.gallery.first?.motion != true)
    #expect(!stillGif.playsInlineLoop)

    let poster = #"{"sha256":"aa","content_type":"image/jpeg","width":100,"height":80,"byte_count":4}"#
    let looped = try APIClient.decoder().decode(Reference.self, from: Data("""
    {"id":"v","kind":"video","title":"Clipe","text":"","url":null,"status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","image":\(poster),"media":{"sha256":"bb","content_type":"video/mp4","duration_seconds":4,"byte_count":20,"has_audio":false,"width":100,"height":80,"loop":true}}
    """.utf8))
    #expect(!looped.gallery.isEmpty)
    #expect(looped.playsInlineLoop)

    let once = try APIClient.decoder().decode(Reference.self, from: Data("""
    {"id":"o","kind":"video","title":"Clipe","text":"","url":null,"status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","image":\(poster),"media":{"sha256":"bb","content_type":"video/mp4","duration_seconds":4,"byte_count":20,"has_audio":true,"width":100,"height":80,"loop":false}}
    """.utf8))
    #expect(!once.playsInlineLoop)
}

@Test func decodesGifMotionPreview() throws {
    let raw = #"{"id":"post","kind":"link","title":"Loop","text":"","url":"https://x.com/a/status/1","status":"ready","revision":1,"created_at":"2026-09-15T15:00:00Z","updated_at":"2026-09-15T15:00:00Z","image":{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12,"preview_kind":"gif","motion":true},"images":[{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12,"preview_kind":"gif","motion":true}]}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.gallery[0].motion == true)
    #expect(ref.gallery[0].previewKind == "gif")
    #expect(ref.gallery[0].isVideoPreview == false)
}

@Test func decodesPostAuthorWithoutMixingAvatarIntoGallery() throws {
    let raw = #"{"id":"post","kind":"link","title":"Mixer no estúdio","text":"","url":"https://x.com/ada/status/1","status":"ready","revision":1,"created_at":"2026-09-17T15:00:00Z","updated_at":"2026-09-17T15:00:00Z","author_image":{"sha256":"cc","content_type":"image/jpeg","width":400,"height":400,"byte_count":8},"image":{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12},"images":[{"sha256":"aa","content_type":"image/jpeg","width":900,"height":600,"byte_count":12}],"source":{"state":"read","url":"https://x.com/ada/status/1","title":"Ada","text":"Um mixer","author_name":"Ada","author_handle":"ada","native_title":false,"fetched_at":"2026-09-17T15:00:00Z","truncated":false,"limitations":[]}}"#
    let ref = try APIClient.decoder().decode(Reference.self, from: Data(raw.utf8))
    #expect(ref.authorImage?.sha256 == "cc")
    #expect(ref.gallery.count == 1)
    #expect(ref.gallery[0].sha256 == "aa")
    #expect(ref.source?.authorName == "Ada")
    #expect(ref.source?.authorHandle == "ada")
    #expect(ref.source?.nativeTitle == false)
}
