# Turns text into embeddings: lists of numbers where texts with similar meaning end up
# close together, so "can I undo removing a person?" lands near "Can I delete an applicant?"
# even though they share no words.
#
# Runs BAAI/bge-small-en-v1.5 locally through ONNX (the informers gem): no API key, nothing
# leaves the machine. The model (~130 MB) downloads to ~/.cache/informers on first use and is
# loaded once per process.
#
#   Embedder.default.embed_documents(["What is a rule? ..."]) # => [[0.012, -0.034, ...]] (384 numbers each)
#   Embedder.default.embed_query("how do rules work")         # => [0.021, ...]
class Embedder
  MODEL = "BAAI/bge-small-en-v1.5"
  DIMENSIONS = 384
  # bge models are trained to put this before search queries (not before documents), which
  # aligns a short question with the longer passages that answer it.
  QUERY_PREFIX = "Represent this sentence for searching relevant passages: "

  LOCK = Mutex.new

  class << self
    attr_writer :default # tests swap in a fake so they don't load the model

    def default
      LOCK.synchronize { @default ||= new }
    end
  end

  # Vectors are normalized to length 1, so cosine similarity is just their dot product.
  def embed_documents(texts)
    return [] if texts.empty?
    pipeline.(texts)
  end

  def embed_query(text)
    pipeline.(QUERY_PREFIX + text)
  end

  private
    def pipeline
      @pipeline || LOCK.synchronize { @pipeline ||= Informers.pipeline("embedding", MODEL) }
    end
end
