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
  IMG_ATTRS_TO_DROP = /\s*(?:src|srcset|sizes|width|height)=["'][^"']*["']/i.freeze

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

  def desktop_width(site)
    (config(site)["desktop_width"] || 960).to_i
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

  def variant_rel(rel_path, format, size)
    if format == :jpeg && size == :full
      rel_path
    else
      suffix = case [format, size]
    when %i[jxl full]      then ".jxl"
    when %i[jxl small]     then ".small.jxl"
    when %i[jpeg small]    then ".small.jpg"
    when %i[jxl desktop]   then ".desktop.jxl"
    when %i[jpeg desktop]  then ".desktop.jpg"
    end
    "assets/downsized/#{output_stem(rel_path)}#{suffix}"
  end
end

def variant_path(site, rel_path, format, size)
  File.join(site.source, variant_rel(rel_path, format, size))
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
def imagemagick7?
  @imagemagick7 ||= system("command -v magick >/dev/null 2>&1")
end

def identify_cmd
  imagemagick7? ? %w[magick identify] : %w[identify]
end

def magick_cmd
  imagemagick7? ? "magick" : "convert"
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

def needs_desktop?(width, site)
  width > desktop_width(site)
end

def expected_outputs(site, rel_path, entry)
  outputs = [variant_path(site, rel_path, :jxl, :full)]
  if entry && entry["small_w"]
    outputs << variant_path(site, rel_path, :jpeg, :small)
    outputs << variant_path(site, rel_path, :jxl, :small)
  end
  if entry && entry["desktop_w"]
    outputs << variant_path(site, rel_path, :jpeg, :desktop)
    outputs << variant_path(site, rel_path, :jxl, :desktop)
  end
  outputs
end

def outputs_present?(site, rel_path, entry)
  entry && expected_outputs(site, rel_path, entry).all? { |path| File.file?(path) }
end

def fresh?(manifest, rel_path, src_path, site)
  entry = manifest[rel_path]
  return false unless entry
  return false unless entry["sha256"] == source_fingerprint(src_path)

  outputs_present?(site, rel_path, entry)
end

def run!(cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  [status.success?, (stderr.strip.empty? ? stdout.strip : stderr.strip)]
end

def run_or_warn!(cmd, rel_path, message)
  ok, err = run!(cmd)
  return true if ok

  Jekyll.logger.warn "PictureTag:", "#{message} for #{rel_path}: #{err}"
  false
end

def encode_jxl!(site, input, output)
  run!(["cjxl", input, output, "--lossless_jpeg=0", "-q", quality(site).to_s, "--quiet"])
end

def convert_image!(site, rel_path)
  src = File.join(site.source, rel_path)
  full_jxl = variant_path(site, rel_path, :jxl, :full)
  small_jpg = variant_path(site, rel_path, :jpeg, :small)
  small_jxl = variant_path(site, rel_path, :jxl, :small)
  oriented = File.join(downsized_dir(site), "#{output_stem(rel_path)}.oriented.jpg")
  FileUtils.mkdir_p(downsized_dir(site))

  dims = image_dimensions(src)
  unless dims
    Jekyll.logger.warn "PictureTag:", "identify failed for #{rel_path}"
    return nil
  end

  full_w, full_h = dims
  small   = needs_small?(full_w, full_h, site)
  desktop = needs_desktop?(full_w, site)
  small_w   = full_w
  desktop_w = full_w

  desktop_jpg = variant_path(site, rel_path, :jpeg, :desktop)
  desktop_jxl = variant_path(site, rel_path, :jxl,  :desktop)

  begin
    return nil unless run_or_warn!([magick_cmd, src, "-auto-orient", "-strip", oriented], rel_path, "magick orient failed")

    ok, err = encode_jxl!(site, oriented, full_jxl)
    unless ok
      Jekyll.logger.warn "PictureTag:", "cjxl failed for #{rel_path}: #{err}"
      return nil
    end

    if small
      resize = "#{max_dim(site)}x#{max_dim(site)}>"
      return nil unless run_or_warn!([magick_cmd, oriented, "-resize", resize, "-quality", quality(site).to_s, small_jpg], rel_path, "magick failed")

      small_dims = image_dimensions(small_jpg)
      small_w, = small_dims if small_dims

      ok, err = encode_jxl!(site, small_jpg, small_jxl)
      unless ok
        Jekyll.logger.warn "PictureTag:", "cjxl small failed for #{rel_path}: #{err}"
        return nil
      end
    else
      FileUtils.rm_f(small_jpg)
      FileUtils.rm_f(small_jxl)
    end

    if desktop
      dw = desktop_width(site)
      return nil unless run_or_warn!([magick_cmd, oriented, "-resize", "#{dw}x>", "-quality", quality(site).to_s, desktop_jpg], rel_path, "magick desktop failed")

      desktop_dims = image_dimensions(desktop_jpg)
      desktop_w, = desktop_dims if desktop_dims

      ok, err = encode_jxl!(site, desktop_jpg, desktop_jxl)
      unless ok
        Jekyll.logger.warn "PictureTag:", "cjxl desktop failed for #{rel_path}: #{err}"
        return nil
      end
    else
      FileUtils.rm_f(desktop_jpg)
      FileUtils.rm_f(desktop_jxl)
    end
  ensure
    FileUtils.rm_f(oriented)
  end

  entry = {
    "sha256"  => source_fingerprint(src),
    "full_w"  => full_w,
    "full_h"  => full_h
  }
  entry["small_w"]   = small_w   if small
  entry["desktop_w"] = desktop_w if desktop
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

def backfill_dimensions!(site, manifest)
  manifest.each_key do |rel_path|
    entry = manifest[rel_path]
    next if entry["full_w"] && entry["full_h"]

    src = File.join(site.source, rel_path)
    next unless File.file?(src)

    dims = image_dimensions(src)
    next unless dims

    entry["full_w"], entry["full_h"] = dims
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

  backfill_dimensions!(site, manifest)
  save_manifest(site, manifest)
  register_downsized_files!(site)
  $stdout.puts "==> PictureTag: converted #{converted}, skipped #{skipped}, failed #{failed}"
end

def srcset_entry(site, rel_path, width)
  "#{url_for(site, rel_path)} #{width}w"
end

def build_srcset(site, rel_path, entry, format)
  parts = []
  if entry["small_w"]
    parts << srcset_entry(site, variant_rel(rel_path, format, :small), entry["small_w"])
  end
  if entry["desktop_w"]
    parts << srcset_entry(site, variant_rel(rel_path, format, :desktop), entry["desktop_w"])
  end
  parts << srcset_entry(site, variant_rel(rel_path, format, :full), entry["full_w"])
  parts.join(", ")
end

def size_attrs(entry)
  w = entry["full_w"]
  h = entry["full_h"]
  return "" unless w && h

  %( width="#{w}" height="#{h}")
end

def wrap_img_tag(site, match, manifest)
  tag = match[0]
  src = match[2]
  rel = normalize_asset_path(src, site)
  return tag unless rel && whitelisted?(rel)

  entry = manifest[rel]
  return tag unless outputs_present?(site, rel, entry)

  sizes = sizes_attr(site)
  jxl_srcset = build_srcset(site, rel, entry, :jxl)
  jpeg_srcset = build_srcset(site, rel, entry, :jpeg)
  img_rel = if entry["desktop_w"]
  variant_rel(rel, :jpeg, :desktop)
elsif entry["small_w"]
  variant_rel(rel, :jpeg, :small)
else
  rel
end

<<~HTML.strip
<picture>
<source type="image/jxl" srcset="#{jxl_srcset}" sizes="#{sizes}">
<source type="image/jpeg" srcset="#{jpeg_srcset}" sizes="#{sizes}">
<img src="#{url_for(site, img_rel)}" srcset="#{jpeg_srcset}" sizes="#{sizes}"#{size_attrs(entry)}#{img_attrs_from(tag)} />
</picture>
HTML
  end

  def img_attrs_from(tag)
    attrs = tag.sub(%r{\A<img\b}i, "").sub(%r{/?>\z}, "")
    attrs = attrs.gsub(IMG_ATTRS_TO_DROP, "")
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

%i[documents pages].each do |type|
  Jekyll::Hooks.register type, :post_render do |doc|
    doc.output = PictureTag.wrap_images(doc.output, doc.site)
  end
end
