#!/usr/bin/ruby
require 'csv'

# Produces rows like this, where - indicates empty
# 'candidate'	dept	party	name	votes	elect
# 'party'		dept	party	-		votes	elect
# 'dept'		dept	-		-		votes	elect 
# 'total'		-		party	-		votes	elect
# 'total'		-		-		-		votes	elect

Row = Struct.new(:type, :dept, :party, :name, :votes, :elect)

class Summary < Struct.new(:dept, :party, :votes, :seats)
	def to_row(type)
		Row.new(type, dept, party, nil, votes, seats)
	end
	def self.aggregate(sums, k = nil, v = nil)
		agg = new(nil, nil, sum_by(sums, &:votes), sum_by(sums, &:seats))
		agg.send(k.to_s + '=', v) if k
		agg
	end
end

def sum_by(a, &block)
	a.map(&block).inject(:+)
end

def elect_dept(dept, rows, all)
	parties = rows.group_by(&:party)
	magnitude = parties.values.map(&:size).max # guessed
	votes = sum_by(rows, &:votes)
	quota = votes.to_f / magnitude # Hare
	
	# Find quotas
	sums = parties.map do |k,v|
		votes = sum_by(v, &:votes)
		Summary.new(dept, k, votes, votes / quota)
	end.sort_by { |s| s.seats % 1 }.reverse # Sort by remainder
	
	# Allocate remainders
	remain = magnitude - sum_by(sums) { |s| s.seats.to_i }
	sums.each_with_index do |s,i|
		s.seats = s.seats.to_i + (i < remain ? 1 : 0)
		
		# Elect candidates
		parties[s.party].sort_by(&:votes).reverse.take(s.seats)
			.each { |r| r.elect = 1 }
	end
	
	# Add summary rows
	sums.sort_by(&:votes).reverse.each { |s| all << s.to_row(:party) }
	all << Summary.aggregate(sums, :dept, dept).to_row(:dept)
	
	return sums
end

def elect(rows)
	sums = rows.group_by(&:dept).map { |k,v| elect_dept(k, v, rows) }.flatten
	
	sums.group_by(&:party).each do |k,v|
		rows << Summary.aggregate(v, :party, k).to_row(:total)
	end
	rows << Summary.aggregate(sums).to_row(:total)
end

def read(io)
	io = open(io) unless io.respond_to?(:read)
	csv = CSV.new(io, :headers => true)

	rows = []
	csv.each do |r|	
		rows << Row.new(:candidate, *r.values_at(*%w[dept party name]),
			r['votes'].to_i, 0)
	end
	csv.close
	
	rows
end

def write(io, rows)
	io = open(io, 'wb') unless io.respond_to?(:read)
	csv = CSV.new(io)
	csv << Row.members # headers
	rows.each { |r| csv << r.values }
	csv.close
end

rows = read(ARGV.shift || $stdin)
elect(rows)
write(ARGV.shift || $stdout, rows)
