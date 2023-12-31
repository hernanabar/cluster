require 'expcalc'
def translate_codes(clusters, hpo)
  translated_clusters = []
  clusters.each do |clusterID, num_of_pats, patientIDs_ary, patient_hpos_ary|
        translate_codes = patient_hpos_ary.map{|patient_hpos| patient_hpos.map{|hpo_code| hpo.translate_id(hpo_code)}}
        translated_clusters << [clusterID, 
          num_of_pats, 
          patientIDs_ary, 
          patient_hpos_ary, 
          translate_codes
        ]
  end
  return translated_clusters
end

def process_dummy_clustered_patients(options, clustered_patients, patient_data, phenotype_ic) # get ic and chromosomes
  ont = Cohort.get_ontology(Cohort.act_ont)
  all_ics = []
  all_lengths = []
  top_cluster_phenotypes = []
  cluster_data_by_chromosomes = []
  multi_chromosome_patients = 0
  processed_clusters = 0
  clustered_patients.sort_by{|cl_id, pat_ids| pat_ids.length }.reverse.each do |cluster_id, patient_ids|
    num_of_patients = patient_ids.length
    next if num_of_patients == 1
    chrs, all_phens, profile_ics, profile_lengths = process_cluster(patient_ids, patient_data, phenotype_ic, options, ont, processed_clusters)
    top_cluster_phenotypes << all_phens if processed_clusters < options[:clusters2show_detailed_phen_data]
    all_ics << profile_ics
    all_lengths << profile_lengths
    if !options[:chromosome_col].nil?
      multi_chromosome_patients += num_of_patients if chrs.length > 1
      chrs.each do |chr, count|
        cluster_data_by_chromosomes << [cluster_id, num_of_patients, chr, count]
      end
    end
    processed_clusters += 1
  end
  return all_ics, all_lengths, cluster_data_by_chromosomes, top_cluster_phenotypes, multi_chromosome_patients
end

def process_cluster(patient_ids, patient_data, phenotype_ic, options, ont, processed_clusters)
  chrs = Hash.new(0)
  all_phens = []
  profile_ics = []
  profile_lengths = []
  patient_ids.each do |pat_id|
    phenotypes = patient_data.get_profile(pat_id) 
    profile_ics << get_profile_ic(phenotypes, phenotype_ic)
    profile_lengths << phenotypes.length
    if processed_clusters < options[:clusters2show_detailed_phen_data]
      phen_names, rejected_codes = ont.translate_ids(phenotypes) #optional
      all_phens << phen_names
    end  
    patient_data.get_vars(pat_id).get_chr.each{|chr| chrs[chr] += 1} if !options[:chromosome_col].nil?
  end
  return chrs, all_phens, profile_ics, profile_lengths 
end

def get_profile_ic(hpo_names, phenotype_ic)
  ic = 0
  profile_length = 0
  hpo_names.each do |hpo_id|
    hpo_ic = phenotype_ic[hpo_id]
    raise("The term #{hpo_id} not exists in the given ic table") if hpo_ic.nil?
    ic += hpo_ic 
    profile_length += 1
  end
  profile_length = 1 if profile_length == 0
  return ic.fdiv(profile_length)
end

def get_summary_stats(patient_data, rejected_patients, hpo_stats, fraction_terms_specific_childs, rejected_hpos)
  stats = []
  stats << ['Unique HPO terms', hpo_stats.length]
  stats << ['Cohort size', patient_data.profiles.length]
  stats << ['Rejected patients by empty profile', rejected_patients.length]
  stats << ['HPOs per patient (average)', patient_data.get_profiles_mean_size]
  stats << ['HPO terms per patient: percentile 90', patient_data.get_profile_length_at_percentile(perc=90)]
  stats << ['Percentage of HPO with more specific children', (fraction_terms_specific_childs * 100).round(4)]
  stats << ['DsI for uniq HP terms', patient_data.get_dataset_specifity_index('uniq')]
  stats << ['DsI for frequency weigthed HP terms', patient_data.get_dataset_specifity_index('weigthed')]
  stats << ['Number of unknown phenotypes', rejected_hpos.length]
  return stats
end

def dummy_cluster_patients(patient_data, matrix_file, clust_pat_file)
  if !File.exists?(matrix_file)
    pat_hpo_matrix, pat_id, hp_id  = patient_data.to_bmatrix
    x_axis_file = matrix_file.gsub('.npy','_x.lst')
    y_axis_file = matrix_file.gsub('.npy','_y.lst')
    pat_hpo_matrix.save(matrix_file, hp_id, x_axis_file, pat_id, y_axis_file)
  end
  system_call(EXTERNAL_CODE, 'get_clusters.R', "-d #{matrix_file} -o #{clust_pat_file} -y #{matrix_file.gsub('.npy','')}") if !File.exists?(clust_pat_file)
  clustered_patients = load_clustered_patients(clust_pat_file)
  return(clustered_patients)
end

def get_mean_size(all_sizes)
    accumulated_size = 0
    number = 0
    all_sizes.each do |size, occurrences|
      accumulated_size += size *occurrences
      number += occurrences
    end
    return accumulated_size.fdiv(number)
end


def get_final_coverage(raw_coverage, bin_size)
	coverage_to_plot = []
	raw_coverage.each do |chr, coverages|
		coverages.each do |start, stop, coverage|
			bin_start = start - start % bin_size
			bin_stop = stop - stop%bin_size
			while bin_start < bin_stop
				coverage_to_plot << [chr, bin_start, coverage]
				bin_start += bin_size
			end
		end
	end
	return coverage_to_plot
end

def get_sor_length_distribution(raw_coverage)
	all_cnvs_length = []
	cnvs_count = []
	raw_coverage.each do |chr, coords_info|
		coords_info.each do |start, stop, pat_records|
			region_length = stop - start + 1
			all_cnvs_length << [region_length, pat_records]
		end
	end
	all_cnvs_length.sort!{|c1, c2| c1[1] <=> c2[1]}
	return all_cnvs_length
end

def calculate_coverage(regions_data, delete_thresold = 0)
	raw_coverage = {}
	n_regions = 0
	patients = 0
	nt = 0
	regions_data.each do |start, stop, chr, reg_id|
		number_of_patients = reg_id.split('.').last.to_i
		if number_of_patients <= delete_thresold
			number_of_patients = 0
		else
			n_regions += 1
			nt += stop - start			
		end
    add_record(raw_coverage, chr, [start, stop, number_of_patients])
		patients += number_of_patients
	end
	return raw_coverage, n_regions, nt, patients.fdiv(n_regions)
end

def get_top_dummy_clusters_stats(top_clust_phen)
  new_cluster_phenotypes = {}
  top_clust_phen.each_with_index do |cluster, clusterID|
    phenotypes_frequency = Hash.new(0)
    total_patients = cluster.length
    cluster.each do |phenotypes|
      phenotypes.each do |p|
        phenotypes_frequency[p] += 1
      end
    end
    new_cluster_phenotypes[clusterID] = [total_patients, phenotypes_frequency.keys, phenotypes_frequency.values.map{|v| v.fdiv(total_patients) * 100}]
  end
  return new_cluster_phenotypes
end

def remove_nested_entries(nested_hash)
  empty_root_ids = []
  nested_hash.each do |root_id, entries|
    entries.select!{|id, val| yield(id, val)}
    empty_root_ids << root_id if entries.empty?
  end
  empty_root_ids.each{|id| nested_hash.delete(id)}
end

def get_semantic_similarity_clustering(options, patient_data, temp_folder)
  template = File.open(File.join(REPORT_FOLDER, 'cluster_report.erb')).read
  hpo = Cohort.get_ontology(Cohort.act_ont)
  reference_profiles = nil
  reference_profiles = load_profiles(options[:reference_profiles], hpo) if !options[:reference_profiles].nil?
  Parallel.each(options[:clustering_methods], in_processes: options[:threads] ) do |method_name|
    matrix_filename = File.join(temp_folder, "similarity_matrix_#{method_name}.npy")
    profiles_similarity_filename = File.join(temp_folder, ['profiles_similarity', method_name].join('_').concat('.txt'))
    clusters_distribution_filename = File.join(temp_folder, ['clusters_distribution', method_name].join('_').concat('.txt'))
    if !File.exists?(matrix_filename)
      if reference_profiles.nil? 
        profiles_similarity = patient_data.compare_profiles(sim_type: method_name.to_sym, external_profiles: reference_profiles)
      else # AS reference profiles are constant, the sematic comparation will be A => B (A reference). So, we have to invert the elements to perform the comparation
        ont = Cohort.get_ontology(:hpo)
        pat_profiles = ont.profiles
        ont.load_profiles(reference_profiles, reset_stored: true)
        profiles_similarity = ont.compare_profiles(sim_type: method_name.to_sym, 
          external_profiles: pat_profiles, 
          bidirectional: false)
        ont.load_profiles(pat_profiles, reset_stored: true)
        profiles_similarity = invert_nested_hash(profiles_similarity)
      end
      remove_nested_entries(profiles_similarity){|id, sim| sim >= options[:sim_thr] } if !options[:sim_thr].nil?
      write_profile_pairs(profiles_similarity, profiles_similarity_filename)
      if reference_profiles.nil?
        axis_file = matrix_filename.gsub('.npy','.lst')
        similarity_matrix, axis_names = profiles_similarity.to_wmatrix(squared: true, symm: true)
        similarity_matrix.save(matrix_filename, axis_names, axis_file)
      else
        axis_file_x = matrix_filename.gsub('.npy','_x.lst')
        axis_file_y = matrix_filename.gsub('.npy','_y.lst')
        similarity_matrix, y_names, x_names = profiles_similarity.to_wmatrix(squared: false, symm: true)
        similarity_matrix.save(matrix_filename, y_names, axis_file_y, x_names, axis_file_x)
      end
    end
    ext_var = ''
    if method_name == 'resnik'
      ext_var = '-m max'
    elsif method_name == 'lin'
      ext_var = '-m comp1'
    end
    cluster_file = "#{method_name}_clusters.txt"
    if !reference_profiles.nil?
      ext_var << ' -s' 
      axis_file = "#{axis_file_y},#{axis_file_x}"
      cluster_file = "#{method_name}_clusters_rows.txt"
    end
    out_file = File.join(temp_folder, method_name)
    system_call(EXTERNAL_CODE, 'plot_heatmap.R', "-y #{axis_file} -d #{matrix_filename} -o #{out_file} -M #{options[:minClusterProportion]} -t dynamic -H #{ext_var}") if !File.exists?(out_file +  '_heatmap.png')
    clusters_codes, clusters_info = parse_clusters_file(File.join(temp_folder, cluster_file), patient_data)  
    write_patient_hpo_stat(get_cluster_metadata(clusters_info), clusters_distribution_filename)
    out_file = File.join(temp_folder, ['clusters_distribution', method_name].join('_'))
    system_call(EXTERNAL_CODE, 'xyplot_graph.R', "-d #{clusters_distribution_filename} -o #{out_file} -x PatientsNumber -y HPOAverage") if !File.exists?(out_file)
    sim_mat4cluster = {}
    if options[:detailed_clusters]
      clusters_codes.each do |cluster|
        cluster_cohort = Cohort.new
        clID, patient_number, patient_ids, hpo_codes = cluster
        patient_ids.each_with_index {|patID, i| cluster_cohort.add_record([patID, hpo_codes[i], []])}
        cluster_profiles = cluster_cohort.profiles
        ref_profile = cluster_cohort.get_general_profile
        hpo.load_profiles({ref: ref_profile}, reset_stored: true)    
        similarities = hpo.compare_profiles(external_profiles: cluster_profiles, sim_type: :lin, bidirectional: false)
        candidate_sim_matrix, candidates, candidates_ids = get_similarity_matrix(ref_profile, similarities[:ref], cluster_profiles, hpo, 100, 100)
        candidate_sim_matrix.unshift(['HP'] + candidates_ids)
        sim_mat4cluster[clID] = candidate_sim_matrix
      end
    end


    clusters = translate_codes(clusters_codes, hpo)
    container = {
      :temp_folder => temp_folder,
      :cluster_name => method_name,
      :clusters => clusters,
      :hpo => hpo,
      :sim_mat4cluster => sim_mat4cluster
     }

    report = Report_html.new(container, 'Patient clusters report')
    report.build(template)
    report.write(options[:output_file]+"_#{method_name}_clusters.html")
    system_call(EXTERNAL_CODE, 'generate_boxpot.R', "-i #{temp_folder} -m #{method_name} -o #{File.join(temp_folder, method_name + '_sim_boxplot')}") if !File.exists?(File.join(temp_folder, 'sim_boxplot.png'))
  end
end

def invert_nested_hash(h)
  new_h = {}
  h.each do |k1, vals1|
    vals1.each do |v1|
      vals1.each do |k2, vals2|
        query = new_h[k2]
        if query.nil?
          new_h[k2] = {k1 => vals2}
        else
          query[k1] = vals2
        end
      end
    end
  end
  return new_h
end

def get_cluster_metadata(clusters_info)
  average_hp_per_pat_distribution = []
  clusters_info.each do |cl_id, pat_info|
      hp_per_pat_in_clust = pat_info.values.map{|a| a.length}
      hp_per_pat_ave = hp_per_pat_in_clust.sum.fdiv(hp_per_pat_in_clust.length)
      average_hp_per_pat_distribution << [pat_info.length, hp_per_pat_ave]
  end
  return average_hp_per_pat_distribution
end