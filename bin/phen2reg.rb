#! /usr/bin/env ruby
# E. Rojano, September 2016
# Program to predict the position from given HPO codes, sorted by their association values.

REPORT_FOLDER=File.expand_path(File.join(File.dirname(__FILE__), '..', 'templates'))
ROOT_PATH = File.dirname(__FILE__)
$: << File.expand_path(File.join(ROOT_PATH, '..', 'lib', 'gephepred'))
require 'generalMethods.rb'
require 'phen2reg_methods.rb'
require 'optparse'

#require 'report_html' # add this require here?

##########################
#OPT-PARSER
##########################

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options]"
  options[:best_thresold] = 1.5
  opts.on("-b", "--best_thresold FLOAT", "Association value thresold") do |best_thresold|
    options[:best_thresold] = best_thresold.to_f
  end

  options[:freedom_degree] = 'prednum'
  opts.on("-d", "--freedom_degree STRING", "Type of freedom degree calculation: prednum, phennum, maxnum") do |fd|
    options[:freedom_degree] = fd
  end 

  options[:html_file] = "patient_profile_report.html"
  opts.on("-F", "--html_file PATH", "HTML file with patient information HPO profile summary") do |html_file|
    options[:html_file] = html_file
  end

  options[:hpo2name_file] = nil
  opts.on("-f", "--hpo2name_file PATH", "Input hpo2name file, used as dictionary") do |hpo2name_file|
    options[:hpo2name_file] = hpo2name_file
  end

  options[:information_coefficient] = nil
  opts.on("-i", "--information_coefficient PATH", "Input file with information coefficients") do |information_coefficient|
    options[:information_coefficient] = information_coefficient
  end
  
  options[:join_regions] = FALSE
    opts.on("-j", "--join_regions", "Join coordinates by borders, if they share the same HPOs") do
  options[:join_regions] = TRUE
  end

  options[:print_matrix] = FALSE
  opts.on('-m', "--print_matrix", "Print output matrix") do 
    options[:print_matrix] = TRUE
  end

  options[:hpo_is_name] = FALSE
    opts.on("-n", "--hpo_is_name", "Set this flag if phenotypes are given as names instead of codes") do
  options[:hpo_is_name] = TRUE
  end  

  options[:output_quality_control] = "output_quality_control.txt"
  opts.on("-O", "--output_quality_control PATH", "Output file with quality control of all input HPOs") do |output_quality_control|
    options[:output_quality_control] = output_quality_control
  end

  options[:output_matrix] = 'output_matrix.txt'
  opts.on("-o", "--output_matrix PATH", "Output matrix file, with associations for each input HPO") do |output_matrix|
    options[:output_matrix] = output_matrix
  end

  options[:prediction_data] = nil
  #chr\tstart\tstop
  opts.on("-p", "--prediction_file PATH", "Input data with HPO codes for predicting their location. It can be either, a file path or string with HPO separated by commas") do |input_path|
    options[:prediction_data] = input_path
  end

  options[:pvalue_cutoff] = 0.1
  opts.on("-P", "--pvalue_cutoff FLOAT", "P-value cutoff") do |pvalue_cutoff|
    options[:pvalue_cutoff] = pvalue_cutoff.to_f
  end

  options[:quality_control] = TRUE
  opts.on("-Q", "--no_quality_control", "Disable quality control") do
    options[:quality_control] = FALSE
  end 

  options[:ranking_style] = ''
  opts.on("-r", "--ranking_style STRING", "Ranking style: mean, fisher, geommean") do |ranking_style|
    options[:ranking_style] = ranking_style
  end

  options[:group_by_region] = TRUE
  opts.on("-S", "--group_by_region", "Disable prediction which HPOs are located in the same region") do
    options[:group_by_region] = FALSE
  end

  options[:html_reporting] = TRUE
  opts.on("-T", "--no_html_reporting", "Disable html reporting") do
    options[:html_reporting] = FALSE
  end 

  options[:training_file] = nil
  #chr\tstart\tstop\tphenotype\tassociation_value
  opts.on("-t", "--training_file PATH", "Input training file, with association values") do |training_path|
    options[:training_file] = training_path
  end

  options[:multiple_profile] = FALSE
    opts.on("-u", "--multiple_profile", "Set if multiple profiles") do
  options[:multiple_profile] = TRUE
  end

  options[:weight_style] = ''
  opts.on("-w", "--weight_style STRING", "Weight style: simple (regions length) or double weight (regions length and patients number") do |weight_style|
    options[:weight_style] = weight_style
  end

end.parse!

##########################
#MAIN
##########################


if File.exist?(options[:prediction_data])
  if !options[:multiple_profile]
    options[:prediction_data] = [File.open(options[:prediction_data]).readlines.map!{|line| line.chomp}]
  else
    multiple_profiles = []
    File.open(options[:prediction_data]).each do |line|
      line.chomp!
      multiple_profiles << line.split('|')
    end
    #STDERR.puts multiple_profiles.inspect
    options[:prediction_data] = multiple_profiles
  end
else
  if !options[:multiple_profile]
    options[:prediction_data] = [options[:prediction_data].split('|')]
  else
    options[:prediction_data] = options[:prediction_data].split('!').map{|profile| profile.split('|')}
  end
end


##########################
#- Loading data


if options[:quality_control]
  hpo_metadata = load_hpo_metadata(options[:hpo2name_file])
  hpo_child_metadata = inverse_hpo_metadata(hpo_metadata)
  hpos_ci_values = load_hpo_ci_values(options[:information_coefficient])
end

hpo_dictionary = load_hpo_dictionary_name2code(options[:hpo2name_file]) if options[:hpo_is_name]
trainingData = load_training_file4HPO(options[:training_file], options[:best_thresold])

##########################
#- HPO PROFILE ANALYSIS

options[:prediction_data].each_with_index do |patient_hpo_profile, patient_number|
  if options[:hpo_is_name]
    patient_hpo_profile.each_with_index do |name, i|
      hpo_code = hpo_dictionary[name]
      if hpo_code.nil?
        STDERR.puts "Warning! Invalid HPO name: #{name}"
        hpo_code = nil
      end
      patient_hpo_profile[i] = hpo_code
    end
    patient_hpo_profile.compact!
  end

  #HPO quality control
  #---------------------------
  characterised_hpos = []
  hpo_metadata = []
  if options[:quality_control]
    #characterised_hpos, hpo_metadata = hpo_quality_control(options[:prediction_data], options[:hpo2name_file], options[:information_coefficient])
    characterised_hpos, hpo_metadata = hpo_quality_control(patient_hpo_profile, hpo_metadata, hpo_child_metadata, hpos_ci_values)
    output_quality_control = File.open(options[:output_quality_control], "w")
    header = ["HPO name", "HPO code", "Exists?", "CI value", "Is child of", "Childs"]
    output_quality_control.puts Terminal::Table.new :headings => header, :rows => characterised_hpos
    output_quality_control.close
  end
  #Prediction steps
  #---------------------------
  hpo_regions = search4HPO(patient_hpo_profile, trainingData)
  if hpo_regions.empty?
  	puts "ProfID:#{patient_number}\tResults not found"
  elsif options[:group_by_region] == FALSE
  	hpo_regions.each do |hpo, regions|
  		regions.each do |region|
  			puts "ProfID:#{patient_number}\t#{hpo}\t#{region.join("\t")}"
  		end
  	end
  elsif options[:group_by_region] == TRUE
  	region2hpo, regionAttributes, association_scores = group_by_region(hpo_regions)
  	hpo_region_matrix = generate_hpo_region_matrix(region2hpo, association_scores, patient_hpo_profile)

    if options[:print_matrix]
      output_matrix = File.open(options[:output_matrix] + "_#{patient_number}", "w")
      output_matrix.puts "Region\t#{patient_hpo_profile.join("\t")}"
      regionAttributes_array = regionAttributes.values
      hpo_region_matrix.each_with_index do |association_values, i|
        chr, start, stop = regionAttributes_array[i]
        output_matrix.puts "#{chr}:#{start}-#{stop}\t#{association_values.join("\t")}"
      end
      output_matrix.close
    end

    scoring_regions(regionAttributes, hpo_region_matrix, options[:ranking_style], options[:pvalue_cutoff], options[:freedom_degree])
    
    adjacent_regions_joined = []
    regionAttributes.each do |regionID, attributes|
      chr, start, stop, patient_ID, region_length, score = attributes
      association_values = association_scores[regionID]
      adjacent_regions_joined << [chr, start, stop, association_values.keys, association_values.values, score]
    end

    #Ranking
    if options[:ranking_style] == 'mean'
      adjacent_regions_joined.sort!{|r1, r2| r2.last <=> r1.last}
    elsif options[:ranking_style] == 'fisher'
      adjacent_regions_joined.sort!{|r1, r2| r1.last <=> r2.last}
    elsif options[:ranking_style] == 'geommean'
      adjacent_regions_joined.sort!{|r1, r2| r2.last <=> r1.last}
    end

  	adjacent_regions_joined.each do |chr, start, stop, hpo_list, association_values, score|
      puts "ProfID:#{patient_number}\t#{chr}\t#{start}\t#{stop}\t#{hpo_list.join(',')}\t#{association_values.join(',')}\t#{score}"
  	end
  end


  #Creating html report
  #-------------------
  report_data(characterised_hpos, adjacent_regions_joined, options[:html_file], hpo_metadata) if options[:html_reporting]
end
