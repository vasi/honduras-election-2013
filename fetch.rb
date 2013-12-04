#!/usr/bin/ruby
require 'typhoeus'
require 'nokogiri'
require 'json'
require 'pp'
require 'csv'

Candidate = Struct.new(:dept, :party, :name, :votes)
Poll = Struct.new(:dept, :counted, :remaining)

class Fetcher	
	Site = 'http://siede.tse.hn/'
	def req(path, **params)
		Typhoeus::Request.new(Site + path, params: params)
	end
	def req_base(o)
		req 'escrutinio/reportes_diputados_general.php'
	end
	def req_dept(o)
		req 'app.php/mapas/diputadospartidospordepartamento',
			evento: o[:event], dep: o[:dept_id]
	end
	def req_party(o)
		req 'app.php/mapas/departamentosvotosdiputadosporpartido',
			evento: o[:event], dept: o[:dept_id], partido: o[:party_id]
	end
	def req_poll(o)
		req 'app.php/mapas/departamentalactasporid?evento=40&nivelelec=2&dept=1',
			evento: o[:event], dept: o[:dept_id], nivelelec: 2
	end
	
	def queue(builder, handler, **params)
		req = method(builder)[**params]
		req.on_complete { |resp| method(handler)[resp, **params] }
		@hydra.queue req
	end
	
	def handle_base(resp, o)
		doc = Nokogiri::HTML(resp.body)
		
		# Find an event id
		md = nil
		doc.css('script').find do |el|
			md = /\bid_ev\b\s*=\s*(\d+)\b/.match(el.text)
		end
		raise "No event ID found" unless md
		event = md[1]
		
		doc.css('#seldepartamentos option').each do |el|
			next if el.text.include?('Seleccione Departamento')
			opts = { event: event, dept_id: el.attr(:value),
				dept_name: el.text }
			queue(:req_dept, :handle_dept, **opts)
			queue(:req_poll, :handle_poll, **opts)
		end
	end
	def handle_dept(resp, o)
		JSON.parse(resp.body).each do |party|
			queue(:req_party, :handle_party,
				party_id: party['partido_id'],
				party_name: party['nombre_partido'], 
				**o)
		end
	end
	def handle_party(resp, o)
		$stderr.puts "Got data for department %s, party %s" %
			[o[:dept_name], o[:party_name]]
		JSON.parse(resp.body)['datadiputados'].each do |data|
			cand = Candidate.new(o[:dept_name], o[:party_name],
				data['nombre'], data['votos'])
			@result_handler[:candidate, cand]
		end
	end
	def handle_poll(resp, o)
		done = todo = 0
		JSON.parse(resp.body)['data']['data'].each do |data|
			case data['name']
				when /^Procesados:/ then done = data['y']
				when /^Por procesar:/ then todo = data['y']
			end
		end
		@result_handler[:poll, Poll.new(o[:dept_name], done, todo)]
	end
	
	def initialize(&result_handler)
		@result_handler = result_handler
		@hydra = Typhoeus::Hydra.hydra
		queue(:req_base, :handle_base)
	end
	
	def run; @hydra.run; end
end

class Writer
	class Data
		def initialize(path, struct)
			@rows = []
			@csv = CSV.open(path, 'wb')
			@csv << struct.members
		end
		def add(v); @rows << v.values; end
		def write
			@rows.sort.each { |r| @csv << r }
			@csv.close
		end
	end
	
	def add(type, v); @data[type].add(v); end
	def csv_init(name, struct)
		path = File.join(@dir, name.to_s + 's.csv')
		(@data ||= {})[name] = Data.new(path, struct)
	end
	
	def initialize(dir, &block)
		@dir = dir || '.'
		csv_init(:candidate, Candidate)
		csv_init(:poll, Poll)
		block[self]
		@data.values.each { |d| d.write }
	end
end

#Typhoeus::Config.verbose = true

Writer.new(ARGV.shift) do |w|
	Fetcher.new { |*a| w.add(*a) }.run
end

