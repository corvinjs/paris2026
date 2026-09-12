# frozen_string_literal: true

require "fileutils"
require "digest"
require "open3"

# Turn markdown image syntax for audio/video files into native <audio>/<video>
# embeds (Obsidian-style: ![](assets/foo.mp4) → <video>, ![](assets/foo.ogg) → <audio>).
module MediaEmbed
  VIDEO_EXT = %w[.mp4 .webm .mov .m4v .ogv].freeze
  AUDIO_EXT = %w[.ogg .mp3 .wav .m4a .flac .aac .opus .3gp].freeze
  VIDEO_REF = %r{assets/[^\s"'<>]+\.(?:mp4|webm|mov|m4v|ogv)}i.freeze
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

  def embed_tag(kind, url, alt, poster = nil)
    fallback = alt && !alt.empty? ? %(<p>#{alt}</p>) : ""

    case kind
    when :video
      poster_attr = poster ? %( poster="#{poster}") : ""
      %(<video controls preload="none" playsinline#{poster_attr} src="#{url}">#{fallback}</video>)
    when :audio
      %(<audio controls preload="metadata" src="#{url}">#{fallback}</audio>)
    end
  end

  def discover_videos(site)
    sources = site.posts.docs.map(&:content)
    site.pages.each do |page|
      sources << (page.data["content"] || (File.file?(page.path) ? File.read(page.path) : nil))
    end
    home = File.join(site.source, "pages", "home.md")
    sources << File.read(home) if File.file?(home)
    sources.compact.flat_map { |text| text.scan(VIDEO_REF) }.uniq.filter_map do |src|
      rel = PictureTag.normalize_asset_path(src, site)
      next unless rel && VIDEO_EXT.include?(File.extname(rel).downcase)

      path = File.join(site.source, rel)
      rel if File.file?(path) && File.readable?(path)
    end
  end

  def thumbnail_rel_path(rel_path)
    rel_path.sub(/\Aassets\//, "assets/downsized/") + ".jpg"
  end

  def thumbnail_path(site, rel_path)
    File.join(site.source, thumbnail_rel_path(rel_path))
  end

  def thumbnail_digest_path(site, rel_path)
    "#{thumbnail_path(site, rel_path)}.sha256"
  end

  def thumbnail_available?(site, rel_path)
    path = thumbnail_path(site, rel_path)
    File.file?(path) && File.size(path).positive?
  rescue SystemCallError
    false
  end

  def thumbnail_fresh?(site, rel_path)
    source = File.join(site.source, rel_path)
    digest_path = thumbnail_digest_path(site, rel_path)
    thumbnail_available?(site, rel_path) &&
      File.file?(digest_path) &&
      File.read(digest_path).strip == Digest::SHA256.file(source).hexdigest
  rescue SystemCallError
    false
  end

  def generate_thumbnail!(site, rel_path)
    return :skipped if thumbnail_fresh?(site, rel_path)

    source = File.join(site.source, rel_path)
    output = thumbnail_path(site, rel_path)
    digest_path = thumbnail_digest_path(site, rel_path)
    token = "#{Process.pid}.#{Thread.current.object_id}"
    temporary = "#{output}.tmp.#{token}.jpg"
    temporary_digest = "#{digest_path}.tmp.#{token}"
    FileUtils.mkdir_p(File.dirname(output))
    stdout, stderr, status = Open3.capture3(
      "ffmpegthumbnailer", "-i", source, "-o", temporary, "-s", "0", "-t", "0", "-q8"
    )
    unless status.success? && File.file?(temporary) && File.size(temporary).positive?
      detail = (stderr.strip.empty? ? stdout.strip : stderr.strip)
      detail = "no output produced" if detail.empty?
      raise detail
    end
    File.rename(temporary, output)
    File.write(temporary_digest, "#{Digest::SHA256.file(source).hexdigest}\n")
    File.rename(temporary_digest, digest_path)
    :generated
  rescue StandardError => e
    Jekyll.logger.warn "MediaEmbed:", "thumbnail failed for #{rel_path}: #{e.message}"
    :failed
  ensure
    FileUtils.rm_f(temporary) if temporary
    FileUtils.rm_f(temporary_digest) if temporary_digest
  end

  def register_thumbnail_files!(site)
    registered = site.static_files.map { |file| file.relative_path.sub(%r{\A/}, "") }
    discover_videos(site).each do |rel_path|
      rel = thumbnail_rel_path(rel_path)
      next unless thumbnail_available?(site, rel_path) && !registered.include?(rel)

      site.static_files << Jekyll::StaticFile.new(site, site.source, File.dirname(rel), File.basename(rel))
      registered << rel
    end
  end

  def ensure_thumbnails!(site)
    generated = skipped = failed = 0
    discover_videos(site).each do |rel_path|
      case generate_thumbnail!(site, rel_path)
      when :generated then generated += 1
      when :skipped then skipped += 1
      when :failed then failed += 1
      end
    end
    register_thumbnail_files!(site)
    $stdout.puts "==> MediaEmbed: generated #{generated}, skipped #{skipped}, failed #{failed}"
  end

  class ThumbnailGenerator < Jekyll::Generator
    safe true
    priority :high

    def generate(site)
      MediaEmbed.ensure_thumbnails!(site)
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
    poster = if kind == :video && rel && thumbnail_available?(site, rel)
               PictureTag.url_for(site, thumbnail_rel_path(rel))
             end
    embed_tag(kind, url, extract_attr(tag, "alt"), poster)
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
