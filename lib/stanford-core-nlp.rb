module StanfordCoreNLP

  VERSION = '0.2.1'

  require 'stanford-core-nlp/jar_loader'
  require 'stanford-core-nlp/java_wrapper'
  require 'stanford-core-nlp/config'

  class << self
    # The path in which to look for the Stanford JAR files,
    # with a trailing slash.
    #
    # The structure of the JAR folder must be as follows:
    #
    # Files:
    #
    #  /stanford-core-nlp.jar
    #  /joda-time.jar
    #  /xom.jar
    #  /bridge.jar*
    #
    # Folders:
    #
    #  /classifiers         # Models for the NER system.
    #  /dcoref              # Models for the coreference resolver.
    #  /taggers             # Models for the POS tagger.
    #  /grammar             # Models for the parser.
    #
    # *The file bridge.jar is a thin JAVA wrapper over the
    # Stanford Core NLP get() function, which allows to
    # retrieve annotations using static classes as names.
    # This works around one of the lacunae of Rjb.
    attr_accessor :jar_path
    # The path to the main folder containing the folders
    # with the individual models inside. By default, this
    # is the same as the JAR path.
    attr_accessor :model_path
    # The flags for starting the JVM machine. The parser
    # and named entity recognizer are very memory consuming.
    attr_accessor :jvm_args
    # A file to redirect JVM output to.
    attr_accessor :log_file
    # The model files for a given language.
    attr_accessor :model_files
  end

  # The default JAR path is the gem's bin folder.
  self.jar_path = File.dirname(__FILE__) + '/../bin/'
  # The default model path is the same as the JAR path.
  self.model_path = self.jar_path
  # Load the JVM with a minimum heap size of 512MB and a
  # maximum heap size of 1024MB.
  self.jvm_args = ['-Xms512M', '-Xmx1024M']
  # Turn logging off by default.
  self.log_file = nil

  # Use models for a given language. Language can be
  # supplied as full-length, or ISO-639 2 or 3 letter
  # code (e.g. :english, :eng or :en will work).
  def self.use(language)
    lang = nil
    self.model_files = {}
    Config::LanguageCodes.each do |l,codes|
      lang = codes[2] if codes.include?(language)
    end
    Config::Models.each do |n, languages|
      models = languages[lang]
      folder = Config::ModelFolders[n]
      if models.is_a?(Hash)
        n = n.to_s
        n += '.model' if n == 'ner'
        models.each do |m, file|
          self.model_files["#{n}.#{m}"] =
          folder + file
        end
      elsif models.is_a?(String)
        self.model_files["#{n}.model"] =
        folder + models
      end
    end
  end

  # Use english by default.
  self.use(:english)

  # Set a model file. Here are the default models for English:
  #
  #    'pos.model' => 'english-left3words-distsim.tagger',
  #    'ner.model.3class' => 'all.3class.distsim.crf.ser.gz',
  #    'ner.model.7class' => 'muc.7class.distsim.crf.ser.gz',
  #    'ner.model.MISCclass' => 'conll.4class.distsim.crf.ser.gz',
  #    'parser.model' => 'englishPCFG.ser.gz',
  #    'dcoref.demonym' => 'demonyms.txt',
  #    'dcoref.animate' => 'animate.unigrams.txt',
  #    'dcoref.female' => 'female.unigrams.txt',
  #    'dcoref.inanimate' => 'inanimate.unigrams.txt',
  #    'dcoref.male' => 'male.unigrams.txt',
  #    'dcoref.neutral' => 'neutral.unigrams.txt',
  #    'dcoref.plural' => 'plural.unigrams.txt',
  #    'dcoref.singular' => 'singular.unigrams.txt',
  #    'dcoref.states' => 'state-abbreviations.txt',
  #    'dcoref.extra.gender' => 'namegender.combine.txt'
  #
  def self.set_model(name, file)
    n = name.split('.')[0].intern
    self.model_files[name] =
    Config::ModelFolders[n] + file
  end

  # Whether the classes are initialized or not.
  @@initialized = false

  # Load the JARs, create the classes.
  def self.init
    unless @@initialized
      self.load_jars
      self.load_default_classes
    end
    @@initialized = true
  end

  # Load a StanfordCoreNLP pipeline with the
  # specified JVM flags and StanfordCoreNLP
  # properties.
  def self.load(*annotators)

    self.init unless @@initialized

    # Prepend the JAR path to the model files.
    properties = {}
    self.model_files.each do |k,v|
      found = false
      annotators.each do |annotator|
        found = true if k.index(annotator.to_s)
        break if found
      end
      next unless found

      f = self.model_path + v
      
      unless File.readable?(f)
        raise "Model file #{f} could not be found. " +
        "You may need to download this file manually "+
        " and/or set paths properly."
      end

      properties[k] = f
    end

    properties['annotators'] =
    annotators.map { |x| x.to_s }.join(', ')
    CoreNLP.new(get_properties(properties))
  end

  # Once it loads a specific annotator model once,
  # the program always loads the same models when
  # you make new pipelines and request the annotator
  # again, ignoring the changes in models.
  #
  # This function kills the JVM and reloads everything
  # if you need to create a new pipeline with different
  # models for the same annotators.
  #def self.reload
  #  raise 'Not implemented.'
  #end

  # Load the jars.
  def self.load_jars
    JarLoader.log(self.log_file)
    JarLoader.jvm_args = self.jvm_args
    JarLoader.jar_path = self.jar_path
    JarLoader.load('joda-time.jar')
    JarLoader.load('xom.jar')
    JarLoader.load('stanford-corenlp.jar')
    JarLoader.load('bridge.jar')
  end

  # Create the Ruby classes corresponding to the StanfordNLP
  # core classes.
  def self.load_default_classes

    const_set(:CoreNLP,
    Rjb::import('edu.stanford.nlp.pipeline.StanfordCoreNLP')
    )

    self.load_klass 'Annotation'
    self.load_klass 'Word', 'edu.stanford.nlp.ling'

    self.load_klass 'MaxentTagger', 'edu.stanford.nlp.tagger.maxent'

    self.load_klass 'CRFClassifier', 'edu.stanford.nlp.ie.crf'

    self.load_klass 'Properties', 'java.util'
    self.load_klass 'ArrayList', 'java.util'

    self.load_klass 'AnnotationBridge', ''

    const_set(:Text, Annotation)

  end

  # Load a class (e.g. PTBTokenizerAnnotator) in a specific
  # class path (default is 'edu.stanford.nlp.pipeline').
  # The class is then accessible under the StanfordCoreNLP
  # namespace, e.g. StanfordCoreNLP::PTBTokenizerAnnotator.
  #
  # List of annotators:
  #
  #  - PTBTokenizingAnnotator - tokenizes the text following Penn Treebank conventions.
  #  - WordToSentenceAnnotator - splits a sequence of words into a sequence of sentences.
  #  - POSTaggerAnnotator - annotates the text with part-of-speech tags.
  #  - MorphaAnnotator - morphological normalizer (generates lemmas).
  #  - NERAnnotator - annotates the text with named-entity labels.
  #  - NERCombinerAnnotator - combines several NER models (use this instead of NERAnnotator!).
  #  - TrueCaseAnnotator - detects the true case of words in free text (useful for all upper or lower case text).
  #  - ParserAnnotator - generates constituent and dependency trees.
  #  - NumberAnnotator - recognizes numerical entities such as numbers, money, times, and dates.
  #  - TimeWordAnnotator - recognizes common temporal expressions, such as "teatime".
  #  - QuantifiableEntityNormalizingAnnotator - normalizes the content of all numerical entities.
  #  - SRLAnnotator - annotates predicates and their semantic roles.
  #  - CorefAnnotator - implements pronominal anaphora resolution using a statistical model (deprecated!).
  #  - DeterministicCorefAnnotator - implements anaphora resolution using a deterministic model (newer model, use this!).
  #  - NFLAnnotator - implements entity and relation mention extraction for the NFL domain.
  def self.load_class(klass, base = 'edu.stanford.nlp.pipeline')
    self.init unless @@initialized
    self.load_klass(klass, base)
  end

  # HCreate a java.util.Properties object from a hash.
  def self.get_properties(properties)
    props = Properties.new
    properties.each do |property, value|
      props.set_property(property, value)
    end
    props
  end

  # Get a Java ArrayList binding to pass lists
  # of tokens to the Stanford Core NLP process.
  def self.get_list(tokens)
    list = StanfordCoreNLP::ArrayList.new
    tokens.each do |t|
      list.add(StanfordCoreNLP::Word.new(t.to_s))
    end
    list
  end

  # Under_case -> CamelCase.
  def self.camel_case(text)
    text.to_s.gsub(/^[a-z]|_[a-z]/) do |a|
      a.upcase
    end.gsub('_', '')
  end

  private
  def self.load_klass(klass, base = 'edu.stanford.nlp.pipeline')
    base += '.' unless base == ''
    const_set(klass.intern,
    Rjb::import("#{base}#{klass}"))
  end

end