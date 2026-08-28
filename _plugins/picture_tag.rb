# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "digest"

module PictureTag
  WHITELIST = %w[.jpg .jpeg .png].freeze
  IMAGE_REF = /assets\/[^\s"'<>]+\.(?:jpg|jpeg|png)/i.freeze
  MANIFEST_NAME = ".manifest.json"
  IMG_TAG = %r{<img\b([^>]*?\bsrc=["']([^"']+)["'][^>]*?)/?>}i

  module_function

  def whitelisted?(path)
    WHITELIST.include?(File.extname(path).downcase)
  end

  def config(site)
    site.config["picture_tag"] || {}
  end

  def max_dim(site)
    (config(site)["max_dim"] || 1600).to_i
  end

  def quality(site)
    (config(site)["quality"] || 85).to_i
  end

  def mobile_breakpoint(site)
    (config(site)["mobile_breakpoint"] || 768).to_i
  end

  def desktop_slot(site)
    config(site)["desktop_slot"] || "1080px"
  end

  def downsized_dir(site)
    File.join(site.source, "assets", "downsized")
  end

  def manifest_path(site)
    File.join(downsized_dir(site), MANIFEST_NAME)
  end

  def output_stem(rel_path)
    File.basename(rel_path, File.extname(rel_path))
  end

  def output_full_jxl(site, rel_path)
    File.join(downsized_dir(site), "#{output_stem(rel_path)}.jxl")
  end

  def output_small_jxl(site, rel_path)
    File.join(downsized_dir(site), "#{output_stem(rel_path)}.small.jxl")
  end

  def output_small_jpg(site, rel_path)
    File.join(downsized_dir(site), "#{output_stem(rel_path)}.small.jpg")
  end

  def rel_full_jxl(rel_path)
    "assets/downsized/#{output_stem(rel_path)}.jxl"
  end

  def rel_small_jxl(rel_path)
    "assets/downsized/#{output_stem(rel_path)}.small.jxl"
  end

  def rel_small_jpg(rel_path)
    "assets/downsized/#{output_stem(rel_path)}.small.jpg"
  end

  def load_manifest(site)
    path = manifest_path(site)
    return {} unless File.file?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    {}
  end

  def save_manifest(site, manifest)
    FileUtils.mkdir_p(downsized_dir(site))
    File.write(manifest_path(site), JSON.pretty_generate(manifest))
  end

  def discover_images(site)
    sources = site.posts.docs.map(&:content)
    site.pages.each do |page|
      next unless page.data["extension"] == "html" || page.path&.end_with?(".md", ".html")

      raw = page.data["content"] || (File.file?(page.path) ? File.read(page.path) : nil)
      sources << raw if raw
    end
    home = File.join(site.source, "pages", "home.md")
    sources << File.read(home) if File.file?(home)

    images = sources.compact.flat_map { |text| text.scan(IMAGE_REF) }.uniq
    images.select do |rel_path|
      whitelisted?(rel_path) && File.file?(File.join(site.source, rel_path))
    end
  end

  def normalize_asset_path(src, site)
    path = src.sub(%r{\A/}, "")
    base = site.baseurl.to_s.sub(%r{\A/}, "").sub(%r{/\z}, "")
    if !base.empty? && path.start_with?("#{base}/")
      path = path.sub(%r{\A#{Regexp.escape(base)}/}, "")
    end
    path if path.start_with?("assets/")
  end

  def url_for(site, rel_path)
    rel = rel_path.sub(%r{\A/}, "")
    base = site.baseurl.to_s.sub(%r{/\z}, "")
    if base.empty? || base == "/"
      rel
    else
      "#{base}/#{rel}"
    end
  end

  def sizes_attr(site)
    bp = mobile_breakpoint(site)
    slot = desktop_slot(site)
    "(max-width: #{bp}px) 100vw, #{slot}"
  end

  def source_fingerprint(path)
    Digest::SHA256.file(path).hexdigest
  end

  # ImageMagick 7: `magick identify …`
  # ImageMagick 6 (Ubuntu CI): standalone `identify` binary — not `convert identify`.
  def identify_cmd
    @identify_cmd ||= if system("command -v magick >/dev/null 2>&1")
                        %w[magick identify]
                      else
                        %w[identify]
                      end
  end

  def image_dimensions(path)
    ok, out = run!([*identify_cmd, "-auto-orient", "-format", "%w %h", path])
    return nil unless ok && out

    w, h = out.split.map(&:to_i)
    return nil if w.zero? || h.zero?

    [w, h]
  end

  def needs_small?(width, height, site)
    limit = max_dim(site)
    width > limit || height > limit
  end

  def expected_outputs(site, rel_path, entry)
    outputs = [output_full_jxl(site, rel_path)]
    if entry && entry["small_w"]
      outputs << output_small_jpg(site, rel_path)
      outputs << output_small_jxl(site, rel_path)
    end
    outputs
  end

  def fresh?(manifest, rel_path, src_path, site)
    entry = manifest[rel_path]
    return false unless entry
    return false unless entry["sha256"] == source_fingerprint(src_path)

    expected_outputs(site, rel_path, entry).all? { |path| File.file?(path) }
  end

  def magick_cmd
    @magick_cmd ||= if system("command -v magick >/dev/null 2>&1")
                      "magick"
                    else
                      "convert"
                    end
  end

  def run!(cmd)
    stdout, stderr, status = Open3.capture3(*cmd)
    [status.success?, (stderr.strip.empty? ? stdout.strip : stderr.strip)]
  end

  def convert_image!(site, rel_path)
    src = File.join(site.source, rel_path)
    full_jxl = output_full_jxl(site, rel_path)
    small_jpg = output_small_jpg(site, rel_path)
    small_jxl = output_small_jxl(site, rel_path)
    oriented = File.join(downsized_dir(site), "#{output_stem(rel_path)}.oriented.jpg")
    FileUtils.mkdir_p(downsized_dir(site))

    dims = image_dimensions(src)
    unless dims
      Jekyll.logger.warn "PictureTag:", "identify failed for #{rel_path}"
      return nil
    end

    full_w, full_h = dims
    small = needs_small?(full_w, full_h, site)
    small_w = full_w

    begin
      ok, err = run!([magick_cmd, src, "-auto-orient", "-strip", oriented])
      unless ok
        Jekyll.logger.warn "PictureTag:", "magick orient failed for #{rel_path}: #{err}"
        return nil
      end

      ok, err = run!(["cjxl", oriented, full_jxl, "--lossless_jpeg=0", "-q", quality(site).to_s, "--quiet"])
      unless ok
        Jekyll.logger.warn "PictureTag:", "cjxl failed for #{rel_path}: #{err}"
        return nil
      end

      if small
        resize = "#{max_dim(site)}x#{max_dim(site)}>"
        ok, err = run!([magick_cmd, oriented, "-resize", resize, "-quality", quality(site).to_s, small_jpg])
        unless ok
          Jekyll.logger.warn "PictureTag:", "magick failed for #{rel_path}: #{err}"
          return nil
        end
        small_dims = image_dimensions(small_jpg)
        if small_dims
          small_w, _small_h = small_dims
        end

        ok, err = run!(["cjxl", small_jpg, small_jxl, "--lossless_jpeg=0", "-q", quality(site).to_s, "--quiet"])
        unless ok
          Jekyll.logger.warn "PictureTag:", "cjxl small failed for #{rel_path}: #{err}"
          return nil
        end
      else
        FileUtils.rm_f(small_jpg)
        FileUtils.rm_f(small_jxl)
      end
    ensure
      FileUtils.rm_f(oriented)
    end

    entry = {
      "sha256" => source_fingerprint(src),
      "full_w" => full_w
    }
    if small
      entry["small_w"] = small_w
    end
    entry
  end

  def register_downsized_files!(site)
    dir = downsized_dir(site)
    return unless File.directory?(dir)

    registered = site.static_files.map { |f| f.relative_path.sub(%r{\A/}, "") }
    Dir.children(dir).each do |name|
      rel = "assets/downsized/#{name}"
      next if registered.include?(rel)

      site.static_files << Jekyll::StaticFile.new(site, site.source, "assets/downsized", name)
    end
  end

  def ensure_variants!(site)
    manifest = load_manifest(site)
    converted = 0
    skipped = 0
    failed = 0

    discover_images(site).each do |rel_path|
      src = File.join(site.source, rel_path)
      if fresh?(manifest, rel_path, src, site)
        skipped += 1
        next
      end

      entry = convert_image!(site, rel_path)
      if entry
        manifest[rel_path] = entry
        converted += 1
      else
        failed += 1
      end
    end

    save_manifest(site, manifest)
    register_downsized_files!(site)
    $stdout.puts "==> PictureTag: converted #{converted}, skipped #{skipped}, failed #{failed}"
  end

  def srcset_entry(site, rel_path, width)
    "#{url_for(site, rel_path)} #{width}w"
  end

  def build_srcset(site, rel_path, entry, type)
    parts = []
    if entry["small_w"]
      small_rel = type == :jxl ? rel_small_jxl(rel_path) : rel_small_jpg(rel_path)
      parts << srcset_entry(site, small_rel, entry["small_w"])
    end
    full_rel = type == :jxl ? rel_full_jxl(rel_path) : rel_path
    parts << srcset_entry(site, full_rel, entry["full_w"])
    parts.join(", ")
  end

  def outputs_exist?(site, rel_path, entry)
    return false unless entry

    expected_outputs(site, rel_path, entry).all? { |path| File.file?(path) }
  end

  def wrap_img_tag(site, match, manifest)
    tag = match[0]
    src = match[2]
    rel = normalize_asset_path(src, site)
    return tag unless rel && whitelisted?(rel)

    entry = manifest[rel]
    return tag unless outputs_exist?(site, rel, entry)

    sizes = sizes_attr(site)
    jxl_srcset = build_srcset(site, rel, entry, :jxl)
    jpeg_srcset = build_srcset(site, rel, entry, :jpeg)
    img_src = entry["small_w"] ? url_for(site, rel_small_jpg(rel)) : url_for(site, rel)

    <<~HTML.strip
      <picture>
        <source type="image/jxl" srcset="#{jxl_srcset}" sizes="#{sizes}">
        <source type="image/jpeg" srcset="#{jpeg_srcset}" sizes="#{sizes}">
        <img src="#{img_src}" srcset="#{jpeg_srcset}" sizes="#{sizes}"#{img_attrs_from(tag)} />
      </picture>
    HTML
  end

  def img_attrs_from(tag)
    attrs = tag.sub(%r{\A<img\b}i, "").sub(%r{/?>\z}, "")
    attrs = attrs.gsub(/\s*src=["'][^"']*["']/i, "")
    attrs = attrs.gsub(/\s*srcset=["'][^"']*["']/i, "")
    attrs = attrs.gsub(/\s*sizes=["'][^"']*["']/i, "")
    attrs = attrs.strip
    attrs.empty? ? "" : " #{attrs}"
  end

  def wrap_imgs_in_fragment(html, site, manifest)
    html.gsub(IMG_TAG) do
      wrap_img_tag(site, Regexp.last_match, manifest)
    end
  end

  def wrap_images(html, site)
    manifest = load_manifest(site)
    html.split(%r{(<picture\b[^>]*>.*?</picture>)}m).map do |part|
      part.start_with?("<picture") ? part : wrap_imgs_in_fragment(part, site, manifest)
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

Jekyll::Hooks.register :documents, :post_render do |doc|
  doc.output = PictureTag.wrap_images(doc.output, doc.site)
end

Jekyll::Hooks.register :pages, :post_render do |page|
  page.output = PictureTag.wrap_images(page.output, page.site)
end
