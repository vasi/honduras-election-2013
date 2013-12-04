#!/usr/bin/ruby
require 'typhoeus'
require 'nokogiri'
require 'json'
require 'pp'
require 'csv'

Candidate = Struct.new(:dept, :party, :name, :votes)

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
			dept_name = el.text
			dept_id = el.attr(:value)
			queue(:req_dept, :handle_dept, event: event,
				dept_id: el.attr(:value), dept_name: el.text)
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
			@result_handler[cand]
		end
	end
	
	def initialize(&result_handler)
		@result_handler = result_handler
		@hydra = Typhoeus::Hydra.hydra
		queue(:req_base, :handle_base)
	end
	
	def run
		@hydra.run
	end
end

class Writer	
	def add(cand); @csv << cand.values; end
	
	def initialize(io, &block)
		io = open(io, 'wb') unless io.respond_to?(:write)
		begin
			@csv = CSV.new(io)
			@csv << Candidate.members
			block[self]
		ensure
			io.close
		end
	end
end

Writer.new(ARGV.shift || $stdout) do |w|
	f = Fetcher.new { |cand| w.add(cand) }
	f.run
end

