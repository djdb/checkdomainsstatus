#!/usr/bin/ruby
# Encoding : utf-8
require 'resolv'
require 'net/http'
require 'logger'

THREADS =	16 # Количество потоков программы

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG
$log.datetime_format = "%Y-%m-%d %H:%M:%S"

$log.info("Старт программы")
mutex = Mutex.new

class Domain
	attr_accessor :fqdn

	def initialize(fqdn)
	# Инициализация класса
		@fqdn = fqdn
	end

	def get_a_record_ip
	# Возвращает IP адреса (A-записи) домена, либо nil если адресов нет
	$log.debug("#{Thread.current[:name]} : Вызов get_a_record_ip для домена #{fqdn}")
		a = nil
		Resolv::DNS.open do |dns|
			a_records = dns.getresources(fqdn, Resolv::DNS::Resource::IN::A)
			a = [] if not a_records.empty?
			a_records.each do |record|
				a << record.address
			end
		end	
	return a
	end

	def get_mx_record_ip
	# Возвращает адреса почтовиков, обслуживающих домен (MX записи), либо nil если адресов нет
	$log.debug("#{Thread.current[:name]} : Вызов get_mx_record_ip для домена #{fqdn}")
		mx = nil
		Resolv::DNS.open do |dns|
			mx_records = dns.getresources(fqdn, Resolv::DNS::Resource::IN::MX)
			mx = [] if not mx_records.empty?
			mx_records.each do |record|
				mx << record.exchange.to_s
			end
		end
	return mx
	end

	def has_web_server?
	# Возвращает true если веб-сервер хоста отвечает (коды в регулярном выражении), либо false если сервер недоступен либо отдает другой код ответа
	$log.debug("#{Thread.current[:name]} : Вызов has_web_server? для домена #{fqdn}")
		answer = false
		begin
			res = Net::HTTP.get_response(URI("http://" + fqdn + "/"))
			rescue => ex
			$log.warn("#{Thread.current[:name]} : Что-то пошло не так во время проведения HTTP-запроса к http://#{fqdn}/ : #{ex.class}: #{ex.message}")
			return false
		end
		return answer = true if res.code =~ /200|301|302/
	end
end # class Domain

# Читаем домены из файла и закидываем в массив
$log.fatal("Не найден файл domains.txt рядом со скриптом! Остановка программы") and exit if not File.exist?("domains.txt")
domains = []
begin
	File.open("domains.txt","r").each {|line| domains << line.chomp}
	rescue => ex
	$log.fatal("Что-то пошло не так при чтении файла domains.txt : #{ex.class}: #{ex.message}")
	$log.fatal("Остановка программы")
	exit
end
domains.uniq!
$log.debug("Из файла прочитано #{domains.count} доменов")

# Решаем, по сколько доменов обработает каждый тред
threadjobs = []
(0..THREADS-1).each {|tn| threadjobs[tn] = domains.count / THREADS}
threadjobs[THREADS-1] += domains.count % THREADS
$log.debug("Распределение заданий по thread'ам: #{threadjobs}")

# Процедура получения нужной информации для каждого треда

def process_domains(array, dom_start, dom_end)
	$log.debug("#{Thread.current[:name]} : process_domains() запущен в треде #{Thread.current} : #{Thread.inspect}")
	local_has_a = 0
	local_has_a_www = 0
	local_has_a_www_mx = 0
	(dom_start..dom_end).each do |domnr|
		$log.debug("#{Thread.current[:name]} : Обработка домена #{array[domnr]}")
		d = Domain.new(array[domnr])
		hasa = false
		hasawww = false
		local_has_a += 1 and hasa = true if not d.get_a_record_ip.nil?
		local_has_a_www += 1 and hasawww = true if hasa and d.has_web_server?
		local_has_a_www_mx += 1 if hasa and hasawww and not d.get_mx_record_ip.nil?
	end
	return local_has_a, local_has_a_www, local_has_a_www_mx
end

# Запуск тредов
has_a = 0
has_a_www = 0
has_a_www_mx = 0

dcount = 0
tn = 0
t = []
threadjobs.each do |tj|
	st = dcount
	en = st + tj - 1
	$log.debug("Поток №#{tn} обработает #{tj} домена(ов): c #{st} по #{en}")
	t[tn] = Thread.new {
		Thread.current[:name]  = "Thread " << st.to_s << ".." << en.to_s
		pd = process_domains(domains, st, en)
		mutex.synchronize {
			has_a += pd[0]
			has_a_www += pd[1]
			has_a_www_mx += pd[2]
			}
		}
	dcount += tj
	tn += 1
end
(0..tn-1).each {|trj| t[trj].join}

# Вывод результатов на экран
puts "--------------------------------------------------------------------------------------"
puts "#{domains.count} доменов обработано, из них:"
puts " #{has_a} доменов имеют запись A"
puts " #{has_a_www} доменов имеют запись A и веб-страницу"
puts " #{has_a_www_mx} доменов имеют запись A, веб-страницу и почтовую запись MX"
puts "--------------------------------------------------------------------------------------"

$log.info("Завершение программы")
