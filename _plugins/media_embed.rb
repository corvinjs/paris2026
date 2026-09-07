# frozen_string_literal: true

# Turn markdown image syntax for audio/video files into native <audio>/<video>
# embeds (Obsidian-style: ![](assets/foo.mp4) → <video>, ![](assets/foo.ogg) → <audio>).
module MediaEmbed
  VIDEO_EXT = %w[.mp4 .webm .mov .m4v .ogv].freeze
  AUDIO_EXT = %w[.ogg .mp3 .wav .m4a .flac .aac .opus .3gp].freeze
  IMG_TAG = %r{<img\b([^>]*?\bsrc=["']([^"']+)["'][^>]*?)/?>}i

  module_function

  def media_kind(path)
    ext = File.extname(path).downcase
    return :video if VIDEO_EXT.include?(ext)
    return :audio if AUDIO_EXT.include?(ext)

    nil
  end

  def extract_attr(tag, name)
    tag.match(/\b#{name}=["']([^"']*)["']/i)&.[](1)
  end

  def embed_tag(site, kind, url, alt)
    fallback = alt && !alt.empty? ? %(<p>#{alt}</p>) : ""
    attrs = %(controls preload="metadata" src="#{url}")

    case kind
    when :video then %(<video #{attrs} playsinline>#{fallback}</video>)
    when :audio then %(<audio #{attrs}>#{fallback}</audio>)
    end
  end

  def replace_img(site, match)
    tag = match[0]
    src = match[2]
    rel = PictureTag.normalize_asset_path(src, site)
    path = rel || src.sub(%r{\A/}, "")
    kind = media_kind(path)
    return tag unless kind

    url = rel ? PictureTag.url_for(site, rel) : src
    embed_tag(site, kind, url, extract_attr(tag, "alt"))
  end

  def transform(html, site)
    html.gsub(IMG_TAG) { replace_img(site, Regexp.last_match) }
  end
end

%i[documents pages].each do |type|
  Jekyll::Hooks.register type, :post_render do |doc|
    doc.output = MediaEmbed.transform(doc.output, doc.site)
  end
end
