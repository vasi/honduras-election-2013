#!/usr/bin/ruby
require 'csv'
require 'unicode_utils'

class Row < Struct.new(:type, :dept, :party, :name, :votes, :elect)
	def initialize(type, dept, party, name, votes, elect)
		super(type.to_sym, dept, party, name, votes.to_i, elect.to_i)
	end
end

def read(io)
	io = open(io) unless io.respond_to?(:read)
	csv = CSV.new(io, :headers => true)

	rows = []
	csv.each { |r| rows << Row.new(*r.values_at(*Row.members.map(&:to_s))) }
	csv.close
	
	rows
end

def thousands(n)
	n.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
end


# Handle long names
Repls = {
	'Independiente Socialista' => 'Ind. Soc.',
	'Unidos Choluteca' => 'Un. Chol.'
}

Format = "%-12s  %10s   %4s   %5d"
DeptThreshold = 3.0 # Min percent to display
def line(party, votes, pct, seats)
	party = Repls[party] if Repls[party]
	pct = pct ? ('%.1f' % pct) : ''  
	Format % [party, thousands(votes), pct, seats]
end
def headers
	Format.gsub(/(%\S+)\S/, '\1s') % %w[Party Votes % Seats]
end
def dash(c = '-'); c * headers.size; end

def table(name, parties, threshold = 0, cands = nil)
	total = parties.map(&:votes).inject(:+)
	seats = parties.map(&:elect).inject(:+)
	
	puts UnicodeUtils.upcase(name)
	puts dash('=')
	puts headers
	puts dash
	
	others = 0
	parties.sort_by(&:votes).reverse.each do |p|
		pct = 100.0 * p.votes / total
		if p.elect > 0 || pct >= threshold
			puts line(p.party, p.votes, pct, p.elect)
		else
			others += p.votes
		end
	end
	puts line('Others', others, 100.0 * others / total, 0) if others > 0
	
	puts dash
	puts line('Total', total, nil, seats)
	puts dash
	
	if cands
		puts 'Deputies elected:'
		puts dash
		cands.select { |c| c.elect > 0 }.sort_by(&:votes).reverse.each do |e|
			puts "%-35s  %8s  %-20s" % [e.name, thousands(e.votes),
				'(%s)' % e.party]
		end
		puts dash
	end
	puts
end

rows = read(ARGV.shift || $stdin)

table('National totals', rows.select { |r| r.type == :total && r.party })
3.times { puts }

rows.select { |r| r.type == :dept }.sort_by(&:dept).each do |d|
	table(d.dept, rows.select { |r| r.type == :party && r.dept == d.dept },
		DeptThreshold)
end
