defmodule Bumblebee.Text.TextEmbedding do
  @moduledoc false

  alias Bumblebee.Shared

  def text_embedding(model_info, tokenizer, opts \\ []) do
    %{model: model, params: params, spec: _spec} = model_info

    opts =
      Keyword.validate!(opts, [
        :compile,
        output_attribute: :pooled_state,
        output_pool: nil,
        embedding_processor: nil,
        defn_options: []
      ])

    output_attribute = opts[:output_attribute]
    output_pool = opts[:output_pool]
    embedding_processor = opts[:embedding_processor]
    defn_options = opts[:defn_options]

    compile =
      if compile = opts[:compile] do
        compile
        |> Keyword.validate!([:batch_size, :sequence_length])
        |> Shared.require_options!([:batch_size, :sequence_length])
      end

    batch_size = compile[:batch_size]
    sequence_length = compile[:sequence_length]

    {_init_fun, encoder} = Axon.build(model)

    embedding_fun = fn params, inputs ->
      output = encoder.(params, inputs)

      output =
        if is_map(output) do
          output[output_attribute]
        else
          output
        end

      output =
        case output_pool do
          nil ->
            output

          :mean_pooling ->
            input_mask_expanded = Nx.new_axis(inputs["attention_mask"], -1)

            output
            |> Nx.multiply(input_mask_expanded)
            |> Nx.sum(axes: [1])
            |> Nx.divide(Nx.sum(input_mask_expanded, axes: [1]))

          other ->
            raise ArgumentError,
                  "expected :output_pool to be one of nil or :mean_pooling, got: #{inspect(other)}"
        end

      output =
        case embedding_processor do
          nil ->
            output

          :l2_norm ->
            Bumblebee.Utils.Nx.normalize(output)

          other ->
            raise ArgumentError,
                  "expected :embedding_processor to be one of nil or :l2_norm, got: #{inspect(other)}"
        end

      output
    end

    Nx.Serving.new(
      fn defn_options ->
        embedding_fun =
          Shared.compile_or_jit(embedding_fun, defn_options, compile != nil, fn ->
            inputs = %{
              "input_ids" => Nx.template({batch_size, sequence_length}, :u32),
              "attention_mask" => Nx.template({batch_size, sequence_length}, :u32)
            }

            [params, inputs]
          end)

        fn inputs ->
          inputs = Shared.maybe_pad(inputs, batch_size)
          embedding_fun.(params, inputs)
        end
      end,
      defn_options
    )
    |> Nx.Serving.process_options(batch_size: batch_size)
    |> Nx.Serving.client_preprocessing(fn input ->
      {texts, multi?} = Shared.validate_serving_input!(input, &Shared.validate_string/1)

      inputs =
        Bumblebee.apply_tokenizer(tokenizer, texts,
          length: sequence_length,
          return_token_type_ids: false
        )

      {Nx.Batch.concatenate([inputs]), multi?}
    end)
    |> Nx.Serving.client_postprocessing(fn {embeddings, _metadata}, multi? ->
      for embedding <- Bumblebee.Utils.Nx.batch_to_list(embeddings) do
        %{embedding: embedding}
      end
      |> Shared.normalize_output(multi?)
    end)
  end
end
