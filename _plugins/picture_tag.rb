# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "digest"

module PictureTag
  WHITELIST = %w[.jpg .jpeg .png].freeze
  FORMATS = %w[jpeg jxl].freeze
  MANIFEST_NAME = ".manifest.json"
  MANIFEST_SCHEMA = 2
  IMAGE_REF = %r{assets/[^\s"'<>]+\.(?:jpg|jpeg|png)}i.freeze
  IMG_TAG = %r{<img\b([^>]*?\bsrc=["']([^"']+)["'][^>]*?)/?>}i
  OWNED_ATTRS = /\s*(?:src|srcset|sizes|width|height)=["'][^"']*["']/i.freeze

  module_function

  def config(site)
    site.config["picture_tag"] || {}
  end

  def whitelisted?(path)
    WHITELIST.include?(File.extname(path).downcase)
  end

  def widths(site)
    Array(config(site)["widths"] || [480, 960, 1440, 1920]).map(&:to_i).select(&:positive?).uniq.sort
  end

  def quality(site)
    (config(site)["quality"] || 85).to_i
  end

  def sizes_attr(site)
    config(site)["sizes"].to_s.empty? ? "(max-width: 799px) calc(100vw - 40px), min(60vw, 960px)" : config(site)["sizes"].to_s
  end

  def downsized_dir(site)
    File.join(site.source, "assets", "downsized")
  end

  def manifest_path(site)
    File.join(downsized_dir(site), MANIFEST_NAME)
  end

  def source_fingerprint(path)
    Digest::SHA256.file(path).hexdigest
  end

  def settings_fingerprint(site)
    Digest::SHA256.hexdigest(JSON.generate("widths" => widths(site), "quality" => quality(site), "formats" => FORMATS))
  end

  def load_manifest(site)
    JSON.parse(File.read(manifest_path(site)))
  rescue Errno::ENOENT, JSON::ParserError
    {"schema" => MANIFEST_SCHEMA, "version" => 1, "entries" => {}}
  end

  def save_manifest(site, manifest)
    FileUtils.mkdir_p(downsized_dir(site))
    tmp = "#{manifest_path(site)}.tmp.#{$$}"
    File.write(tmp, JSON.pretty_generate(manifest) + "\n")
    File.rename(tmp, manifest_path(site))
  ensure
    FileUtils.rm_f(tmp) if tmp
  end

  def discover_images(site)
    sources = site.posts.docs.map(&:content)
    site.pages.each do |page|
      sources << (page.data["content"] || (File.file?(page.path) ? File.read(page.path) : nil))
    end
    home = File.join(site.source, "pages", "home.md")
    sources << File.read(home) if File.file?(home)
    sources.compact.flat_map { |text| text.scan(IMAGE_REF) }.uniq.select do |rel|
      whitelisted?(rel) && File.file?(File.join(site.source, rel))
    end
  end

  def normalize_asset_path(src, site)
    path = src.sub(%r{\A/}, "")
    base = site.baseurl.to_s.sub(%r{\A/}, "").sub(%r{/\z}, "")
    path = path.sub(%r{\A#{Regexp.escape(base)}/}, "") if !base.empty? && path.start_with?("#{base}/")
    path if path.start_with?("assets/")
  end

  def url_for(site, rel_path)
    base = site.baseurl.to_s.sub(%r{/\z}, "")
    "#{base}/#{rel_path.sub(%r{\A/}, "")}"
  end

  def run!(cmd)
    stdout, stderr, status = Open3.capture3(*cmd)
    [status.success?, (stderr.strip.empty? ? stdout.strip : stderr.strip)]
  end

  def imagemagick7?
    @imagemagick7 = system("command -v magick >/dev/null 2>&1") if @imagemagick7.nil?
    @imagemagick7
  end

  def identify_cmd
    imagemagick7? ? %w[magick identify] : %w[identify]
  end

  def magick_cmd
    imagemagick7? ? "magick" : "convert"
  end

  def image_dimensions(path)
    ok, out = run!([*identify_cmd, "-auto-orient", "-format", "%w %h", path])
    return nil unless ok
    w, h = out.split.map(&:to_i)
    w.positive? && h.positive? ? [w, h] : nil
  end

  def candidate_widths(source_width, site)
    ((widths(site).select { |w| w < source_width } + [ [source_width, 1920].min ]).uniq.sort)
  end

  def output_rel(rel_path, width, format)
    stem = rel_path.sub(/\.[^.]+\z/, "")
    ext = format == "jpeg" ? "jpg" : "jxl"
    "assets/downsized/#{stem}.#{width}.#{ext}"
  end

  def output_path(site, rel_path, width, format)
    File.join(site.source, output_rel(rel_path, width, format))
  end

  def expected_outputs(site, entry)
    Array(entry && entry["candidates"]).flat_map do |candidate|
      FORMATS.map { |format| File.join(site.source, candidate[format]["rel_path"]) }
    end
  end

  def fresh?(manifest, rel_path, src_path, site)
    entry = manifest.fetch("entries", {})[rel_path]
    entry && entry["source_sha256"] == source_fingerprint(src_path) &&
      entry["settings_fingerprint"] == settings_fingerprint(site) &&
      expected_outputs(site, entry).all? { |path| File.file?(path) }
  end

  def encode_jxl!(input, output, site)
    run!(["cjxl", input, output, "--lossless_jpeg=0", "-q", quality(site).to_s, "--quiet"])
  end

  def convert_image!(site, rel_path)
    src = File.join(site.source, rel_path)
    source_w, source_h = image_dimensions(src)
    return nil unless source_w && source_h
    candidates = candidate_widths(source_w, site)
    token = "#{Process.pid}.#{Thread.current.object_id}"
    oriented = File.join(downsized_dir(site), ".#{Digest::SHA256.hexdigest(rel_path)[0, 12]}.#{token}.oriented.jpg")
    generated = []
    replacements = []
    FileUtils.mkdir_p(downsized_dir(site))
    begin
      ok, error = run!([magick_cmd, src, "-auto-orient", "-strip", oriented])
      raise "orientation failed: #{error}" unless ok
      candidates.each do |width|
        files = {}
        FORMATS.each do |format|
          rel = output_rel(rel_path, width, format)
          path = File.join(site.source, rel)
          tmp = "#{path}.tmp.#{token}.#{format == "jpeg" ? "jpg" : "jxl"}"
          FileUtils.mkdir_p(File.dirname(path))
          actual = nil
          if format == "jpeg"
            ok, error = run!([magick_cmd, oriented, "-resize", "#{width}x", "-quality", quality(site).to_s, tmp])
          else
            jpeg_tmp = "#{path}.input.#{token}.jpg"
            ok, error = run!([magick_cmd, oriented, "-resize", "#{width}x", "-quality", quality(site).to_s, jpeg_tmp])
            ok, error = encode_jxl!(jpeg_tmp, tmp, site) if ok
            actual = image_dimensions(jpeg_tmp) if ok
            FileUtils.rm_f(jpeg_tmp)
          end
          raise "conversion failed: #{error}" unless ok
          actual ||= image_dimensions(tmp)
          raise "wrong output width #{actual && actual[0]} (expected #{width})" unless actual && actual[0] == width
          replacements << [tmp, path]
          files[format] = {"rel_path" => rel, "width" => actual[0], "height" => actual[1]}
        end
        candidates[candidates.index(width)] = files
      end
      replacements.each do |tmp, path|
        File.rename(tmp, path)
        generated << path
      end
    rescue StandardError => e
      generated.each { |path| FileUtils.rm_f(path) }
      replacements.each { |tmp,| FileUtils.rm_f(tmp) }
      Jekyll.logger.warn "PictureTag:", "#{e.message} for #{rel_path}"
      return nil
    ensure
      FileUtils.rm_f(oriented)
    end
    {
      "sha256" => source_fingerprint(src),
      "source_sha256" => source_fingerprint(src),
      "settings_fingerprint" => settings_fingerprint(site),
      "oriented_width" => source_w,
      "oriented_height" => source_h,
      "source_width" => source_w,
      "source_height" => source_h,
      "candidates" => candidates
    }
  end

  def register_downsized_files!(site)
    dir = downsized_dir(site)
    return unless File.directory?(dir)
    registered = site.static_files.map { |file| file.relative_path.sub(%r{\A/}, "") }
    Dir.glob(File.join(dir, "**", "*")).select { |path| File.file?(path) }.each do |path|
      rel = path.delete_prefix("#{site.source}/")
      next if rel == "assets/downsized/#{MANIFEST_NAME}" || registered.include?(rel)
      relative_dir = File.dirname(rel)
      name = File.basename(rel)
      site.static_files << Jekyll::StaticFile.new(site, site.source, relative_dir, name)
    end
  end

  def ensure_variants!(site)
    old = load_manifest(site)
    manifest = {
      "schema" => MANIFEST_SCHEMA,
      "version" => 1,
      "settings_fingerprint" => settings_fingerprint(site),
      "entries" => {}
    }
    converted = skipped = 0
    discover_images(site).each do |rel_path|
      src = File.join(site.source, rel_path)
      if fresh?(old, rel_path, src, site)
        manifest["entries"][rel_path] = old["entries"][rel_path]
        skipped += 1
      else
        entry = convert_image!(site, rel_path)
        raise "image conversion failed for #{rel_path}" unless entry
        manifest["entries"][rel_path] = entry
        converted += 1
      end
    end
    save_manifest(site, manifest)
    register_downsized_files!(site)
    $stdout.puts "==> PictureTag: converted #{converted}, skipped #{skipped}, failed 0"
  end

  def build_srcset(site, entry, format)
    entry["candidates"].map { |candidate| "#{url_for(site, candidate[format]["rel_path"])} #{candidate[format]["width"]}w" }.join(", ")
  end

  def img_attrs_from(tag)
    attrs = tag.sub(%r{\A<img\b}i, "").sub(%r{/?>\z}, "").gsub(OWNED_ATTRS, "").strip
    attrs.empty? ? "" : " #{attrs}"
  end

  def wrap_img_tag(site, match, manifest)
    tag, src = match[0], match[2]
    rel = normalize_asset_path(src, site)
    entry = rel && manifest.fetch("entries", {})[rel]
    return tag unless rel && whitelisted?(rel) && entry && expected_outputs(site, entry).all? { |path| File.file?(path) }
    jpeg = build_srcset(site, entry, "jpeg")
    jxl = build_srcset(site, entry, "jxl")
    smallest = entry["candidates"].first["jpeg"]["rel_path"]
    <<~HTML.strip
      <picture>
      <source type="image/jxl" srcset="#{jxl}" sizes="#{sizes_attr(site)}">
      <source type="image/jpeg" srcset="#{jpeg}" sizes="#{sizes_attr(site)}">
      <img src="#{url_for(site, smallest)}" srcset="#{jpeg}" sizes="#{sizes_attr(site)}" width="#{entry["source_width"]}" height="#{entry["source_height"]}"#{img_attrs_from(tag)} />
      </picture>
    HTML
  end

  def wrap_images(html, site)
    manifest = load_manifest(site)
    html.split(%r{(<picture\b[^>]*>.*?</picture>)}m).map do |part|
      part.start_with?("<picture") ? part : part.gsub(IMG_TAG) { wrap_img_tag(site, Regexp.last_match, manifest) }
    end.join
  end

  class VariantGenerator < Jekyll::Generator
    safe true
    priority :high
    def generate(site)
      PictureTag.ensure_variants!(site)
    end
  end
end

%i[documents pages].each do |type|
  Jekyll::Hooks.register type, :post_render do |doc|
    doc.output = PictureTag.wrap_images(doc.output, doc.site)
  end
end
