#! /usr/bin/env ruby


ROOT_PATH = File.dirname(__FILE__)
REPORT_FOLDER = File.expand_path(File.join(ROOT_PATH, '..', 'templates'))
EXTERNAL_DATA = File.expand_path(File.join(ROOT_PATH, '..', 'external_data'))
HPO_FILE = File.join(EXTERNAL_DATA, 'hp.json')
$: << File.expand_path(File.join(ROOT_PATH, '..', 'lib', 'pets'))

require 'optparse'
require 'report_html'
require 'semtools'
require 'generalMethods.rb'

#############################################################################################
## METHODS
############################################################################################
def procces_patient_data(patient_data, hpo)
	clean_profiles = {}
	all_hpo = []
	patient_data.each do |pat_id, data|
		profile = hpo.clean_profile_hard(data.first.map{|c| c.to_sym})
		if !profile.empty?
			clean_profiles[pat_id] = profile
			all_hpo.concat(profile)
		end
	end
	ref_prof = hpo.clean_profile_hard(all_hpo.uniq)
	return ref_prof, clean_profiles
end

#############################################################################################
## OPTPARSE
############################################################################################

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options]"

  options[:chromosome_col] = nil
  opts.on("-c", "--chromosome_col INTEGER/STRING", "Column name if header is true, otherwise 0-based position of the column with the chromosome") do |data|
    options[:chromosome_col] = data
  end

  options[:pat_id_col] = nil
  opts.on("-d", "--pat_id_col INTEGER/STRING", "Column name if header is true, otherwise 0-based position of the column with the patient id") do |data|
    options[:pat_id_col] = data
  end

  options[:end_col] = nil
  opts.on("-e", "--end_col INTEGER/STRING", "Column name if header is true, otherwise 0-based position of the column with the end mutation coordinate") do |data|
    options[:end_col] = data
  end
  
  options[:header] = true
  opts.on("-H", "--header", "File has a line header. Default true") do 
    options[:header] = false
  end

  options[:output_file] = 'report.html'
  opts.on("-o", "--output_file PATH", "Output paco file with HPO names") do |data|
    options[:output_file] = data
  end

  options[:input_file] = nil
  opts.on("-P", "--input_file PATH", "Input file with PACO extension") do |value|
    options[:input_file] = value
  end

  options[:hpo_col] = nil
  opts.on("-p", "--hpo_term_col INTEGER/STRING", "Column name if header true or 0-based position of the column with the HPO terms") do |data|
    options[:hpo_col] = data
  end

  options[:start_col] = nil
  opts.on("-s", "--start_col INTEGER/STRING", "Column name if header is true, otherwise 0-based position of the column with the start mutation coordinate") do |data|
    options[:start_col] = data
  end

  options[:hpo_separator] = '|'
  opts.on("-S", "--hpo_separator STRING", "Set which character must be used to split the HPO profile. Default '|'") do |data|
    options[:hpo_separator] = data
  end

	 opts.on_tail("-h", "--help", "Show this message") do
	    puts opts
	    exit
	  end
end.parse!

#############################################################################################
## MAIN
############################################################################################

patient_data = load_patient_cohort(options)

hpo_file = !ENV['hpo_file'].nil? ? ENV['hpo_file'] : HPO_FILE
hpo = Ontology.new
hpo.read(hpo_file)


ref_profile, clean_profiles = procces_patient_data(patient_data, hpo)

hpo.load_profiles({ref: ref_profile})

similarities = hpo.compare_profiles(external_profiles: clean_profiles, sim_type: :lin, bidirectional: false)

candidate_sim_matrix, candidates, candidates_ids = get_similarity_matrix(ref_profile, similarities[:ref], clean_profiles, hpo, 40)
candidate_sim_matrix.unshift(['HP'] + candidates_ids)

template = File.open(File.join(REPORT_FOLDER, 'similarity_matrix.erb')).read
container = {
	similarity_matrix: candidate_sim_matrix
}
report = Report_html.new(container, 'Similarity matrix')
report.build(template)
report.write(options[:output_file])