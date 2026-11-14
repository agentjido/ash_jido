# Used by "mix format"
[
  import_deps: [:ash, :ash_jido, :jido],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
