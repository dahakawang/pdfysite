# encoding: UTF-8
# 
require "net/http"
require "cgi/cookie"
require "nokogiri"
require "json"
require "fileutils"
require "open-uri"
require "erb"
require "singleton"
require "ostruct"
require "ruby-debug"
require 'digest'
require "active_support"
require "active_support/core_ext/string"
require "zip"

def get_xsrf()
	uri = URI("http://www.zhihu.com")

	res = Net::HTTP.get_response uri
	if(! res.is_a? Net::HTTPSuccess)
		raise RuntimeError.new("Failed to get xsrf value from site " + uri.to_s)
	end

	doc = Nokogiri::HTML(res.body)
	doc.css('form[action=\'/login\'] input[name=_xsrf]').each do |link|
		return link.attribute("value").to_s
	end

	raise RuntimeError.new("Failed to get xsrf value from site " + uri.to_s)
end

def login(username, password)
	xsrf = get_xsrf();
	uri = URI("http://www.zhihu.com/login")
	res = Net::HTTP.post_form(uri, _xsrf: xsrf, email: username, password: password, rememberme: "y")

	cookies = CGI::Cookie.parse(res["set-cookie"])
	secure = {"q_c0" => cookies["q_c0"].value[0], "q_c1" => cookies["q_c1"].value[0], "_xsrf" => xsrf}
	
	if(!secure.has_key?("q_c0") || !secure.has_key?("q_c1") || secure["q_c0"].empty? || secure["q_c1"].empty?)
		raise RuntimeError.new("failed to get session cookie") 
	end

	secure
end

def extract_urls(msg)
	json = JSON.parse(msg)
	urls = []

	json["msg"].each do |item|
		doc = Nokogiri::HTML(item)
		link = "http://www.zhihu.com" + doc.css('a.question_link')[0].attribute("href").to_s
		urls << link
	end

	urls
end

def get_msg_at(offset, session)
	uri = URI("http://www.zhihu.com/node/ProfileFollowedQuestionsV2")

	Net::HTTP.start(uri.host, uri.port) do |http|
		req = Net::HTTP::Post.new uri
		cookie = session.map { |key, val|  key.to_s + "=" + val.to_s}.join("; ")
		req["Cookie"] = cookie

		req.set_form_data(method: "next", params: "{\"offset\":#{offset}}", _xsrf: session["_xsrf"])


		res = http.request req

		return res.body
	end
end

def get_all_links(session)
	cur = 0
	links = []
	loop do
		msg = extract_urls(get_msg_at(cur, session))

		cur += msg.length
		links.push(*msg)
		break if msg.length == 0
	end

	links
end


#session = login("5", "")
#links =  get_all_links session

#==========================

links = [
#"http://www.zhihu.com/question/24853558",
#"http://www.zhihu.com/question/20084859",
#"http://www.zhihu.com/question/20071999",
#"http://www.zhihu.com/question/19774690",
"http://www.zhihu.com/question/19729338",
"http://www.zhihu.com/question/19962467",
"http://www.zhihu.com/question/19996012"
]


def mkdir(dir_name)
	unless File.directory?(dir_name)
  	FileUtils.mkdir_p(dir_name)
	end
end


def build_dir
	mkdir "output"
	mkdir "output/OEBPS"
	mkdir "output/OEBPS/image"
	FileUtils.copy_entry "template/META-INF", "output/META-INF"
	FileUtils.copy_entry "template/mimetype", "output/mimetype"
	FileUtils.cp("template/typo.css", "output/OEBPS")
end

def save_html(html, count, length)
	filename = "question-" + count.to_s.rjust(length, "0") + ".xhtml"
	File.open("output/OEBPS/" + filename, 'w') {|f| f.write(html) }
end

def get_local_question(index, length)
	filename = "output/OEBPS/question-" + index.to_s.rjust(length, "0") + ".xhtml"
	return nil if !File.exist?(filename)

	doc = nil
	File.open(filename, "r") do |file|
		doc = Nokogiri::XML(file.read)
	end

	doc.css("img").each do |img|
		return nil if !File.exist?("output/OEBPS/" + img["src"])
	end
	doc
end

def get_http_page(url)
	data = Net::HTTP.get_response(URI(url))
	if ! data.is_a?(Net::HTTPSuccess)
		raise RuntimeError.new("Cannot download page: #{url.strip} #{data.class.name}") 
	end
	data.body
end

def get_http_image(url)
	data = Net::HTTP.get_response(URI(url))

	# if the image is not available, we just ignore it
	if data.is_a?(Net::HTTPNotFound)
		return ""
	end

	if ! data.is_a?(Net::HTTPSuccess)
		puts data.class.name
		raise RuntimeError.new("Cannot download : #{url.strip}") 
	end
	data.body
end

def save_image(url)
	# Zhihu will cache image on different server, so we compute the filename outof the url
	filename = Digest::MD5.hexdigest(url[url.rindex("/")..-1]) + url[url.rindex(".")..-1]
	filepath = "output/OEBPS/image/" + filename;

	return if File.exist?(filepath)  # cache the images

	data = get_http_image(url)
  File.open(filepath,"wb") do |file|
     file.puts data
  end


	"image/" + filename
end

class Answer
	attr_reader :author, :content
	def initialize(author, content)
		@author = author
		@content = content
	end
end

class Question
	attr_reader :title, :des, :answers
	def initialize(title, des)
		@title = title
		@des = des
		@answers = []
	end

	def append(answer)
		@answers << answer
	end

	def get_binding
		return binding
	end
end

class Renderer
	include Singleton

	def initialize
		file = File.open("template/zhihu.html.erb", "rb:UTF-8")
		@template = file.read
	end

	def render(question)
		ERB.new(@template).result(binding)
	end
end

def get_question(url)
	data = get_http_page(url)
	doc = Nokogiri::HTML(data)

	title = doc.css(".zm-item-title")[0].content.strip
	des = doc.css("#zh-question-detail div")[0]
	des["class"] = "description"
	question = Question.new(title, des)

	doc.css(".zm-item-answer").each do |item|
		author = item.css(".zm-item-answer-author-wrap")[0].content.strip

		content = item.css(".zm-item-rich-text div")[0]
		content["class"] = "conent"

		question.append Answer.new(author, content)
	end

	question
end


def relocate(doc)
	doc.css("img").each do |img|
		img_url_origin = img["data-original"]
		img_url_actual = img["data-actualsrc"]
		
		url = (img_url_origin != nil) ? img_url_origin : img_url_actual
		if(url == nil)
			next
		end
		img.xpath("@*").remove
		img_url = save_image(url)
		img["src"] = img_url
	end
end

def delete_no_script(doc)
	doc.css('noscript').remove
end

def delete_expand(doc)
	doc.css('.toggle-expand').remove
end

def process_node(node)
	delete_no_script(node)
	relocate(node)
	delete_expand(node)
end

def process(question)
	process_node(question.des)


	question.answers.each do |answer|
		process_node(answer.content)
	end
end

def download_question(link, index, length, &blk)
	cached = get_local_question(index, length) # page and image are all cached?

	if(cached == nil)
		#puts "actual download #{link.strip} - #{index}"
		question = get_question(link)

		#download&relocation images
		process(question);

		html = Renderer.instance.render question
		save_html(html, index, length)
	end
end



class EpubBuilder
	include Singleton

	def initialize
		file = File.open("template/OEBPS/content.opf.erb", "rb:UTF-8")
		@opf_template = file.read
		file = File.open("template/OEBPS/toc.ncx.erb", "rb:UTF-8")
		@ncx_template = file.read

		@article_per_book = 60
	end

	def list_files(path)
		groups = []

		files = Dir[path + "/OEBPS/*.xhtml"]
		files.sort!
		(files.group_by {|obj| files.index(obj) / @article_per_book }).each do |key, value|
			groups << {contents: value}
		end


		groups.each do |group|
			images = []
			group[:contents].each do |article|
				doc = Nokogiri::XML(open(article))
				doc.css("img").each do |img|
					if(img["src"]!= nil && !img["src"].empty? && img["src"].start_with?("image"))
						images << img["src"]
					end
				end
			end
			group[:images] = images
			group[:styles] = Dir[path + "/OEBPS/*.css"]

			group[:contents].map! {|file| file.slice!(path + "/OEBPS/"); file}
			group[:styles].map! {|file| file.slice!(path + "/OEBPS/"); file}
		end

		groups
	end

	def build_opf(id, images, styles, contents)
		xml = ERB.new(@opf_template).result(binding)
		filename = "output/OEBPS/content.opf"
		File.open(filename, 'w') {|f| f.write(xml) }
	end

	def get_title(filename)
		filepath = "output/OEBPS/" + filename
		File.open(filepath, 'r') do |f|
			doc = Nokogiri::XML(f.read);

			title = doc.css("title")[0].content.strip
			
			return title
		end
		raise RuntimeError.new("Cannot get file title")
	end

	def get_order(content, contents)
		(1 + contents.index(content)).to_s
	end

	def get_id(content, contents)
		"navPoint-" + get_order(content, contents)
	end

	def build_ncx(id, contents)
		xml = ERB.new(@ncx_template).result(binding)
		filename = "output/OEBPS/toc.ncx"
		File.open(filename, 'w') {|f| f.write(xml) }
	end

	def build_package(id, group)
		epub_file = "output/知乎问答集锦#{id}.epub"
		FileUtils.rm(epub_file) if File.exist?(epub_file)
		
		Zip::File.open(epub_file, Zip::File::CREATE) do |file|
			file.add("mimetype", "output/mimetype")
			file.add("META-INF/container.xml", "output/META-INF/container.xml")
			file.add("OEBPS/content.opf", "output/OEBPS/content.opf")
			file.add("OEBPS/toc.ncx", "output/OEBPS/toc.ncx")

			group[:contents].each do |content_file|
				file.add("OEBPS/" + content_file, "output/OEBPS/" + content_file)
			end

			group[:styles].each do |style_file|
				file.add("OEBPS/" + style_file, "output/OEBPS/" + style_file)
			end

			group[:images].each do |image_file|
				file.add("OEBPS/" + image_file, "output/OEBPS/" + image_file)
			end
		end
		#`cd output; zip -0Xq  知乎问答集锦.epub mimetype`
		#`cd output; zip -Xr9Dq 知乎问答集锦.epub *`
	end

	def build_epub(path)
		file_groups = list_files(path)

		file_groups.each do |group|
		# group = file_groups[0]
			id = file_groups.index(group) + 1
			styles = group[:styles]
			images = group[:images]
			contents = group[:contents]

			contents.sort!
			build_opf(id, images, styles, contents)
			build_ncx(id, contents)

			build_package(id, group)
		end
	end
end


class DownloadManager

	def initialize
		@total = 0
		@current = 0
		@error = 0
		@max_retry_time = 5
		@max_threads = 100
		@mutex = Mutex.new
		@error_url = []
	end

	def done_one
		@current = @current + 1;
	end

	def log(str)
		@mutex.synchronize {
			puts(str)
		}
	end

	def print_status
		puts("Status #{@current}/#{@total}, #{@error} errors")
	end

	def increase_done
		@mutex.synchronize {
			@current += 1
			print_status
		}
	end

	def increase_error(url)
		@mutex.synchronize {
			@error += 1
			@error_url << url
		}
	end

	def worker(links, start_index, length)
		links.each do |link|
			retried = 0
			begin
				download_question(link, links.index(link) + start_index, length)
			rescue StandardError => e
				if(retried < @max_retry_time)
					retried += 1
					sleep(2)
					retry
				else
					log("Failed to download " + link.strip + " after retried #{@max_retry_time} times, will skip. " + e.to_s)
					increase_error(link.strip)
					next
				end
			end

			increase_done
		end
	end

	def split(links, count, total_group)
		raise RuntimeError.new("count must be more than 0") if count <= 0
		link_group = []

		(0...total_group).each do |i|
			if(i < total_group - 1)
				link_group << links[(i*count)...(i*count+count)]
			else
				link_group << links[(i*count)..-1]
			end
		end
		link_group
	end

	def validate(link_group)
		raise RuntimeError.new("The link group is not as much as thread count") if link_group.length != @max_threads

		count = 0
		link_group.each do |group|
			count += group.length
		end
		raise RuntimeError.new("The total link in link group is wrong") if count != @total
	end

	def download(links)
		length = 11 #Math.log10(links.length)
		@total = links.length

		#spawn new threads to do the work
		threads = []
		@max_threads = 1 if links.length < @max_threads
		count = (links.length.to_f / @max_threads.to_f).floor
		link_group = split(links, count, @max_threads)

		validate(link_group)

		puts "Download using #{@max_threads} threads..."
		(0...@max_threads).each do |i|
			threads << Thread.new {
				worker(link_group[i], i*count, length)
			}
		end

		threads.each {|t| t.join} #wait for all thread

		puts "Following page failed to download"
		@error_url.each do |url|
			puts url
		end
	end
end

class Zhihu
	include Singleton

	def get_cache()
		return nil if(!File.exist?("question.list")) 

		puts "Using cached list"
		File.open("question.list", "r") do |file|
			return file.readlines
		end
	end

	def cache(links)
		File.open("question.list", "w") do |file|
			links.each do |link|
				file.puts link
			end
		end
	end

	def get_links(username, password)
		links = get_cache()
		return links if(links != nil)

		session = login(username, password)
		links = get_all_links session
		cache links
		links
	end


	def pdfy(username, password)
		puts "Getting List..."
		links = get_links(username, password)

		puts "Building output directory"
		build_dir

		puts "downloading..."
		DownloadManager.new.download(links)
		
		
		EpubBuilder.instance.build_epub("output")
	end
end

Zhihu.instance.pdfy "502823090@qq.com", ""
#
# DownloadManager.new.download(links)
# 
#EpubBuilder.instance.build_epub("output")


