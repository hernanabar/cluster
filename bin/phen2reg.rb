#! /usr/bin/env ruby
# Rojano E. & Seoane P., September 2016
# Program to predict the position from given HPO codes, sorted by their association values.

ROOT_PATH = File.dirname(__FILE__)
$: << File.expand_path(File.join(ROOT_PATH, '..', 'lib', 'pets'))

require 'optparse'
require 'report_html'
require 'semtools'
require 'pets'

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

  options[:hpo_file] = nil
  opts.on("-f", "--hpo_file PATH", "Input hp.obo file") do |hpo_file|
    options[:hpo_file] = hpo_file
  end

  options[:information_coefficient] = nil
  opts.on("-i", "--information_coefficient PATH", "Input file with information coefficients") do |information_coefficient|
    options[:information_coefficient] = information_coefficient
  end

  options[:join_adyacent_regions] = false
  opts.on('-j', "--join_adyacent_regions", "When a group of regions are adyacent they are merged in a single one with averaged parameters. The phenotypes in the regions must be shared across them.") do 
    options[:join_adyacent_regions] = true
  end

  options[:retrieve_kegg_data] = false
  opts.on('-k', "--retrieve_kegg_data", "Add KEGG data to prediction report") do 
    options[:retrieve_kegg_data] = true
  end


  options[:print_matrix] = false
  opts.on('-m', "--print_matrix", "Print output matrix") do 
    options[:print_matrix] = true
  end

  options[:max_number] = 10
  opts.on("-M", "--max_number INTEGER", "Max number of regions to take into account") do |max_number|
    options[:max_number] = max_number.to_i
  end

  options[:hpo_is_name] = false
    opts.on("-n", "--hpo_is_name", "Set this flag if phenotypes are given as names instead of codes") do
  options[:hpo_is_name] = true
  end  

  options[:output_quality_control] = "output_quality_control.txt"
  opts.on("-O", "--output_quality_control PATH", "Output file with quality control of all input HPOs") do |output_quality_control|
    options[:output_quality_control] = output_quality_control
  end

  options[:output_matrix] = 'output_matrix.txt'
  opts.on("-o", "--output_matrix PATH", "Output matrix file, with associations for each input HPO") do |output_matrix|
    options[:output_matrix] = output_matrix
  end

  options[:output_path] = './'
  opts.on("-O", "--output_path PATH", "General output folder path, takes precedence for other options") do |output|
    options[:output_path] = output
  end

  options[:prediction_data] = nil
  #chr\tstart\tstop
  opts.on("-p", "--prediction_file PATH", "Input data with HPO codes for predicting their location. It can be either, a file path or string with HPO separated by pipes (|)") do |input_path|
    options[:prediction_data] = input_path
  end

  options[:pvalue_cutoff] = 0.1
  opts.on("-P", "--pvalue_cutoff FLOAT", "P-value cutoff") do |pvalue_cutoff|
    options[:pvalue_cutoff] = pvalue_cutoff.to_f
  end

  options[:quality_control] = true
  opts.on("-Q", "--no_quality_control", "Disable quality control") do
    options[:quality_control] = false
  end 

  options[:ranking_style] = ''
  opts.on("-r", "--ranking_style STRING", "Ranking style: mean, fisher, geommean") do |ranking_style|
    options[:ranking_style] = ranking_style
  end

  options[:write_hpo_recovery_file] = true
  opts.on("-s", "--write_hpo_recovery_file", "Disable write hpo recovery file") do
    options[:write_hpo_recovery_file] = false
  end

  options[:group_by_region] = true
  opts.on("-S", "--group_by_region", "Disable prediction which HPOs are located in the same region") do
    options[:group_by_region] = false
  end

  options[:html_reporting] = true
  opts.on("-T", "--no_html_reporting", "Disable html reporting") do
    options[:html_reporting] = false
  end 

  options[:training_file] = nil
  #chr\tstart\tstop\tphenotype\tassociation_value
  opts.on("-t", "--training_file PATH", "Input training file, with association values") do |training_path|
    options[:training_file] = training_path
  end

  options[:multiple_profile] = false
    opts.on("-u", "--multiple_profile", "Set if multiple profiles") do
  options[:multiple_profile] = true
  end

  options[:hpo_recovery] = 50
  opts.on("-y", "--hpo_recovery INTEGER", "Minimum percentage of HPO terms to consider predictions") do |hpo_recovery|
    options[:hpo_recovery] = hpo_recovery.to_f
  end

end.parse!

##########################
#PATHS
##########################
all_paths = {code: File.join(File.dirname(__FILE__), '..')}
all_paths[:external_data] = File.join(all_paths[:code], 'external_data')
all_paths[:gene_data] = File.join(all_paths[:external_data], 'gene_data.gz')
all_paths[:biosystems_gene] = File.join(all_paths[:external_data], 'biosystems_gene.gz')
all_paths[:biosystems_info] = File.join(all_paths[:external_data], 'bsid2info.gz')
all_paths[:gene_data_with_pathways] = File.join(all_paths[:external_data], 'gene_data_with_pathways.gz')
all_paths[:gene_location] = File.join(all_paths[:external_data], 'gene_location.gz')

output_folder = File.expand_path(options[:output_path])
Dir.mkdir(output_folder) if !File.exists?(output_folder)

##########################
#MAIN
##########################

#- Loading patient profiles
#------------------------------
if File.exist?(options[:prediction_data]) # From file
  if !options[:multiple_profile]
    options[:prediction_data] = [File.open(options[:prediction_data]).readlines.map!{|line| line.chomp}]
  else
    options[:prediction_data] = File.open(options[:prediction_data]).readlines.map!{|line| line.chomp.split('|')}
  end
else # if you want to add phenotypes through the terminal
  if !options[:multiple_profile]
    options[:prediction_data] = [options[:prediction_data].split('|')]
  else
    options[:prediction_data] = options[:prediction_data].split('!').map{|profile| profile.split('|')}
  end
end
#- Loading data
#------------------------------
# hpo = Ontology.new
# hpo.load_data(options[:hpo_file])
hpo = Ontology.new(file: options[:hpo_file], load_file: true)
trainingData = load_training_file4HPO(options[:training_file], options[:best_thresold])
hpos_ci_values = load_hpo_ci_values(options[:information_coefficient]) if options[:quality_control]

genes_with_kegg = {}
gene_location = {}
if options[:retrieve_kegg_data] 
 gene_location, genes_with_kegg = get_and_parse_external_data(all_paths)
end

#- HPO PROFILE ANALYSIS
#---------------------------------
phenotypes_by_patient = {}
predicted_hpo_percentage = {}
options[:prediction_data].each_with_index do |patient_hpo_profile, patient_number|
      if options[:hpo_is_name]
        # patient_hpo_profile, rejected = hpo.translate_names2codes(patient_hpo_profile)
        patient_hpo_profile, rejected = hpo.translate_names(patient_hpo_profile)
        STDERR.puts "Phenotypes #{rejected.join(",")} in patient #{patient_number} not exist"
      end

      patient_hpo_profile, rejected_hpos = hpo.check_ids(patient_hpo_profile.map{|h| h.to_sym})
      STDERR.puts "WARNING: unknown CODES #{rejected_hpos.join(',')}" if !rejected_hpos.empty?
      
      characterised_hpos = []
      if options[:quality_control]
        characterised_hpos = hpo_quality_control(patient_hpo_profile, hpos_ci_values, hpo)
        File.open(File.join(output_folder, options[:output_quality_control]), "w") do |f|
          header = ["HPO name", "HPO code", "Exists?", "CI value", "Is child of", "Childs"]
          f.puts Terminal::Table.new :headings => header, :rows => characterised_hpos
        end
      end
      patient_hpo_profile, parental_hpo = hpo.remove_ancestors_from_profile(patient_hpo_profile)
      patient_hpo_profile.map!{|h| h.to_s} # Convert codes to string to be compatible with search4HPO like methods
      phenotypes_by_patient[patient_number] = patient_hpo_profile

      #Prediction steps
      #---------------------------
      hpo_regions = search4HPO(patient_hpo_profile, trainingData)
      if hpo_regions.empty?
        puts "ProfID:#{patient_number}\tResults not found"
      elsif options[:group_by_region] == false
        hpo_regions.each do |hpo, regions|
          regions.each do |region|
            puts "ProfID:#{patient_number}\t#{hpo}\t#{region.join("\t")}"
          end
        end
      elsif options[:group_by_region] == true
        region2hpo, regionAttributes, association_scores = group_by_region(hpo_regions)
        #STDERR.puts patient_hpo_profile.inspect
        #add_parentals_of_not_found_hpos_in_regions(patient_hpo_profile, trainingData, region2hpo, regionAttributes, association_scores, hpo_metadata)
        #STDERR.puts patient_hpo_profile.inspect
        null_value = 0
        hpo_region_matrix = generate_hpo_region_matrix(region2hpo, association_scores, patient_hpo_profile, null_value)
        if options[:print_matrix]
          mat_output = File.join(output_folder, options[:output_matrix]) + "_#{patient_number}"
          save_patient_matrix(mat_output, patient_hpo_profile, regionAttributes, hpo_region_matrix)
        end

        adjacent_regions_joined = []
        scoring_regions(regionAttributes, hpo_region_matrix, options[:ranking_style], options[:pvalue_cutoff], options[:freedom_degree], null_value)
        if regionAttributes.empty?
          puts "ProfID:#{patient_number}\tResults not found"
        else    
          regionAttributes.each do |regionID, attributes|
            chr, start, stop, patient_ID, region_length, score = attributes
            association_values = association_scores[regionID]
            adjacent_regions_joined << [chr, start, stop, association_values.keys, association_values.values, score]
          end
          adjacent_regions_joined = join_regions(adjacent_regions_joined) if options[:join_adyacent_regions] # MOVER A ANTES DE CONSTRUIR LA MATRIZ
          
          #Ranking
          if options[:ranking_style] == 'fisher'
            adjacent_regions_joined.sort!{|r1, r2| r1.last <=> r2.last}
          else
            adjacent_regions_joined.sort!{|r1, r2| r2.last <=> r1.last}
          end
          patient_original_phenotypes = phenotypes_by_patient[patient_number]
          calculate_hpo_recovery_and_filter(adjacent_regions_joined, patient_original_phenotypes, predicted_hpo_percentage, options[:hpo_recovery], patient_number)
          if adjacent_regions_joined.empty?
            puts "ProfID:#{patient_number}\tResults not found"
          else
            adjacent_regions_joined = adjacent_regions_joined.shift(options[:max_number]) if !options[:max_number].nil?
            adjacent_regions_joined.each do |chr, start, stop, hpo_list, association_values, score|
              puts "ProfID:#{patient_number}\t#{chr}\t#{start}\t#{stop}\t#{hpo_list.join(',')}\t#{association_values.join(',')}\t#{score}"
            end
          end
        end
      end #elsif

      pathway_stats = {}
      if options[:retrieve_kegg_data]
        genes_found = []
        genes_found_attributes = {}
        adjacent_regions_joined.each do |adjacent_region|
          ref_chr, ref_start, ref_stop = adjacent_region
          chr_genes = gene_location[ref_chr]
          genes = []
          chr_genes.each do |gene_name, gene_start, gene_stop|
                genes << gene_name if coor_overlap?(ref_start, ref_stop, gene_start, gene_stop)
          end
          genes_found << genes
        end

        genes_with_kegg_data = []
        genes_found.each do |genes|
          genes_cluster = []
          genes.each do |gene|
            query = genes_with_kegg[gene]
            genes_cluster << [gene, query]
          end
          genes_with_kegg_data << genes_cluster
        end
        pathway_stats = compute_pathway_enrichment(genes_with_kegg_data, genes_with_kegg)
        pathway_stats.sort!{|p1, p2| p1.last <=> p2.last}
      end

      #Creating html report
      #-------------------

      report_data(
        characterised_hpos, 
        adjacent_regions_joined, 
        File.join(output_folder, options[:html_file]), 
        hpo, 
        genes_with_kegg_data, 
        pathway_stats
      ) if options[:html_reporting]
end # end each_with_index

if options[:write_hpo_recovery_file]
  File.open(File.join(output_folder, 'output_profile_recovery'), 'w') do |f|
    predicted_hpo_percentage.each do |patient, percentage|  
      percentage.each do |perc|
        f.puts "ProfID:#{patient}\t#{perc.inspect}"
      end
    end
  end
end
