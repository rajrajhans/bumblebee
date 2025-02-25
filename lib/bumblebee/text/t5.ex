defmodule Bumblebee.Text.T5 do
  alias Bumblebee.Shared

  options =
    [
      vocab_size: [
        default: 32128,
        doc: """
        the vocabulary size of the token embedding. This corresponds to the number of distinct
        tokens that can be represented in model input and output
        """
      ],
      tie_word_embeddings: [
        default: true,
        doc: """
        whether or not to tie encoder and decoder token embedding
        """
      ],
      hidden_size: [
        default: 512,
        doc: "the dimensionality of hidden layers"
      ],
      attention_head_size: [
        default: 64,
        doc: "the size of the key, value, and query projection per attention head"
      ],
      encoder_num_blocks: [
        default: 6,
        doc: "the number of Transformer blocks in the encoder"
      ],
      decoder_num_blocks: [
        default: 6,
        doc: "the number of Transformer blocks in the decoder"
      ],
      encoder_num_attention_heads: [
        default: 8,
        doc: "the number of attention heads for each attention layer in the encoder"
      ],
      decoder_num_attention_heads: [
        default: 8,
        doc: "the number of attention heads for each attention layer in the decoder"
      ],
      intermediate_size: [
        default: 2048,
        docs:
          "the dimensionality of the intermediate layer in the transformer feed-forward network (FFN) in the encoder"
      ],
      relative_attention_num_buckets: [
        default: 32,
        docs: "the number of buckets to use for the relative attention bias"
      ],
      relative_attention_max_distance: [
        default: 128,
        docs: "the maximum distance of the relative attention bias"
      ],
      activation: [
        default: :relu,
        doc: "the activation function"
      ],
      ffn_gated_activation: [
        default: false,
        doc:
          "whether to use a gated variant of the activation function in the feed-forward network (FFN)"
      ],
      dropout_rate: [
        default: 0.1,
        doc: "the dropout rate for encoder and decoder"
      ],
      initializer_scale: [
        default: 1.0,
        doc:
          "the standard deviation of the normal initializer used for initializing kernel parameters"
      ],
      layer_norm_epsilon: [
        default: 1.0e-6,
        doc: "the epsilon used by the layer normalization layers"
      ]
    ] ++
      Shared.common_options([
        :output_hidden_states,
        :output_attentions,
        :num_labels,
        :id_to_label
      ]) ++ Shared.token_options(decoder_start_token_id: 0)

  @moduledoc """
  T5 model family.

  ## Architectures

    * `:base` - plain T5 without any head on top

    * `:for_conditional_generation` - T5 with a language modeling
      head. The head returns logits for each token in the original
      sequence

    * `:encoder` - just the encoder part of the base model

  ## Inputs

    * `"input_ids"` - `{batch_size, sequence_length}`

      Indices of input sequence tokens in the vocabulary.

    * `"attention_mask"` - `{batch_size, sequence_length}`

      Mask indicating which tokens to attend to. This is used to ignore
      padding tokens, which are added when processing a batch of sequences
      with different length.

    * `"attention_head_mask"` - `{encoder_num_blocks, encoder_num_attention_heads}`

      Mask to nullify selected heads of the self-attention blocks in
      the encoder.

    * `"input_embeddings"` - `{batch_size, sequence_length, hidden_size}`

      Embedded representation of `"input_ids"`, which can be specified
      for more control over how `"input_ids"` are embedded than the
      model's internal embedding lookup. If `"input_embeddings"` are present,
      then `"input_ids"` will be ignored.

    * `"decoder_input_ids"` - `{batch_size, target_sequence_length}`

      Indices of decoder input sequence tokens in the vocabulary. If not
      present and `"input_ids"` is, it will be generated by shifting
      each token in `"input_ids"` to the right once.

    * `"decoder_attention_mask"` - `{batch_size, target_sequence_length}`

      Mask indicating which decoder tokens to attend to. This is used
      to ignore padding tokens, which are added when processing a batch
      of sequences with different length.

    * `"decoder_attention_head_mask"` - `{decoder_num_blocks, decoder_num_attention_heads}`

      Mask to nullify selected heads of the self-attention blocks in
      the decoder.

    * `"decoder_input_embeddings"` - `{batch_size, sequence_length, hidden_size}`

      Embedded representation of `"decoder_input_ids"`, which can be
      specified for more control over how `"decoder_input_ids"` are
      embedded than the model's internal embedding lookup. If
      `"decoder_input_embeddings"` are present, then `"decoder_input_ids"`
      will be ignored.

    * `"encoder_hidden_state"` - `{batch_size, sequence_length, hidden_size}`

      Last hidden state output from the encoder. This hidden state is
      used in cross-attention blocks in the decoder. If specified, the
      model will skip the encoding process and use this value directly
      for cross-attentions in the decoder.

    * `"cross_attention_head_mask"` - `{decoder_num_blocks, decoder_num_attention_heads}`

      Mask to nullify selected heads of the cross-attention blocks in
      the decoder with shape.

    * `"cache"`

      A container with cached layer results used to speed up sequential
      decoding (autoregression). With cache, certain hidden states are
      taken from the cache, rather than recomputed on every decoding
      pass. The cache should be treated as opaque and initialized with
      `Bumblebee.Text.Generation.init_cache/4`.

  ## Configuration

  #{Shared.options_doc(options)}
  """

  defstruct [architecture: :base] ++ Shared.option_defaults(options)

  @behaviour Bumblebee.ModelSpec
  @behaviour Bumblebee.Configurable
  @behaviour Bumblebee.Text.Generation

  import Bumblebee.Utils.Model, only: [join: 2]

  alias Bumblebee.Layers

  @impl true
  def architectures(),
    do: [:base, :for_conditional_generation, :encoder]

  @impl true
  def config(spec, opts \\ []) do
    spec
    |> Shared.put_config_attrs(opts)
    |> Shared.validate_label_options()
  end

  @impl true
  def input_template(_spec) do
    %{
      "input_ids" => Nx.template({1, 1}, :u32)
    }
  end

  @impl true
  def init_cache(spec, batch_size, max_length, inputs) do
    encoder_sequence_length =
      if encoder_hidden_state = inputs["encoder_hidden_state"] do
        Nx.axis_size(encoder_hidden_state, 1)
      end

    Layers.Decoder.init_cache(batch_size, max_length,
      hidden_size: spec.hidden_size,
      attention_head_size: spec.attention_head_size,
      decoder_num_attention_heads: spec.decoder_num_attention_heads,
      encoder_num_attention_heads: spec.encoder_num_attention_heads,
      decoder_num_blocks: spec.decoder_num_blocks,
      encoder_sequence_length: encoder_sequence_length
    )
  end

  @impl true
  def traverse_cache(_spec, cache, fun) do
    Layers.Decoder.traverse_cache(cache, fun)
  end

  @impl true
  def model(%__MODULE__{architecture: :base} = spec) do
    inputs = encoder_decoder_inputs(spec)

    inputs
    |> core(spec)
    |> Layers.output()
  end

  def model(%__MODULE__{architecture: :for_conditional_generation} = spec) do
    inputs = encoder_decoder_inputs(spec)
    outputs = core(inputs, spec)

    hidden_state =
      if spec.tie_word_embeddings do
        Axon.nx(outputs.hidden_state, &Nx.multiply(&1, Nx.rsqrt(spec.hidden_size)))
      else
        outputs.hidden_state
      end

    logits = language_modeling_head(hidden_state, spec, name: "language_modeling_head")

    Layers.output(%{
      logits: logits,
      decoder_hidden_states: outputs.decoder_hidden_states,
      decoder_attentions: outputs.decoder_attentions,
      cross_attentions: outputs.cross_attentions,
      encoder_hidden_state: outputs.encoder_hidden_state,
      encoder_hidden_states: outputs.encoder_hidden_states,
      encoder_attentions: outputs.encoder_attentions,
      cache: outputs.cache
    })
  end

  def model(%__MODULE__{architecture: :encoder} = spec) do
    inputs = encoder_inputs(spec)

    embeddings =
      embedder(inputs["input_ids"], inputs["input_embeddings"], spec, name: "encoder_embedder")

    outputs =
      encoder(embeddings, inputs["attention_mask"], inputs["attention_head_mask"], spec,
        name: "encoder"
      )

    Layers.output(%{
      hidden_state: outputs.hidden_state,
      hidden_states: outputs.hidden_states,
      attentions: outputs.attentions
    })
  end

  defp encoder_inputs(spec) do
    shape = {nil, nil}
    hidden_shape = {nil, nil, spec.hidden_size}

    attention_head_mask_shape = {spec.encoder_num_blocks, spec.encoder_num_attention_heads}

    Bumblebee.Utils.Model.inputs_to_map([
      Axon.input("input_ids", optional: true, shape: shape),
      Axon.input("attention_mask", optional: true, shape: shape),
      Axon.input("attention_head_mask", optional: true, shape: attention_head_mask_shape),
      Axon.input("input_embeddings", optional: true, shape: hidden_shape)
    ])
  end

  defp encoder_decoder_inputs(spec) do
    shape = {nil, nil}
    hidden_shape = {nil, nil, spec.hidden_size}

    encoder_attention_head_mask_shape =
      {spec.encoder_num_blocks, spec.encoder_num_attention_heads}

    decoder_attention_head_mask_shape =
      {spec.decoder_num_blocks, spec.decoder_num_attention_heads}

    Bumblebee.Utils.Model.inputs_to_map([
      Axon.input("input_ids", optional: true, shape: shape),
      Axon.input("attention_mask", optional: true, shape: shape),
      Axon.input("attention_head_mask", optional: true, shape: encoder_attention_head_mask_shape),
      Axon.input("input_embeddings", optional: true, shape: hidden_shape),
      Axon.input("decoder_input_ids", optional: true, shape: shape),
      Axon.input("decoder_attention_mask", optional: true, shape: shape),
      Axon.input("decoder_attention_head_mask",
        optional: true,
        shape: decoder_attention_head_mask_shape
      ),
      Axon.input("decoder_input_embeddings", optional: true, shape: hidden_shape),
      Axon.input("encoder_hidden_state", optional: true, shape: hidden_shape),
      Axon.input("cross_attention_head_mask",
        optional: true,
        shape: decoder_attention_head_mask_shape
      ),
      Axon.input("cache", optional: true)
    ])
  end

  defp core(inputs, spec) do
    encoder_outputs =
      Layers.if_present inputs["encoder_hidden_state"] do
        %{
          hidden_state: inputs["encoder_hidden_state"],
          hidden_states: Layers.none(),
          attentions: Layers.none()
        }
      else
        embeddings =
          embedder(
            inputs["input_ids"],
            inputs["input_embeddings"],
            spec,
            name: "encoder_embedder"
          )

        embeddings
        |> encoder(inputs["attention_mask"], inputs["attention_head_mask"], spec, name: "encoder")
        |> Map.take([:hidden_state, :hidden_states, :attentions])
      end

    decoder_input_ids =
      Layers.default inputs["decoder_input_ids"] do
        Layers.shift_tokens_right(inputs["input_ids"], spec.decoder_start_token_id)
      end

    embeddings =
      embedder(decoder_input_ids, inputs["decoder_input_embeddings"], spec,
        name: "decoder_embedder"
      )

    decoder_outputs =
      decoder(
        embeddings,
        inputs["decoder_attention_mask"],
        inputs["decoder_attention_head_mask"],
        encoder_outputs.hidden_state,
        inputs["attention_mask"],
        inputs["cross_attention_head_mask"],
        inputs["cache"],
        spec,
        name: "decoder"
      )

    %{
      hidden_state: decoder_outputs.hidden_state,
      decoder_hidden_states: decoder_outputs.hidden_states,
      decoder_attentions: decoder_outputs.attentions,
      cross_attentions: decoder_outputs.cross_attentions,
      cache: decoder_outputs.cache,
      encoder_hidden_state: encoder_outputs.hidden_state,
      encoder_hidden_states: encoder_outputs.hidden_states,
      encoder_attentions: encoder_outputs.attentions
    }
  end

  defp embedder(input_ids, input_embeddings, spec, opts) do
    name = opts[:name]

    input_embeddings =
      Layers.default input_embeddings do
        Axon.embedding(input_ids, spec.vocab_size, spec.hidden_size,
          name: join(name, "token_embedding")
        )
      end

    input_embeddings
  end

  defp encoder(hidden_state, attention_mask, attention_head_mask, spec, opts) do
    name = opts[:name]

    encoder_outputs =
      Layers.Transformer.blocks(hidden_state,
        attention_mask: attention_mask,
        attention_head_mask: attention_head_mask,
        num_blocks: spec.encoder_num_blocks,
        num_attention_heads: spec.encoder_num_attention_heads,
        hidden_size: spec.hidden_size,
        kernel_initializer: kernel_initializer(spec),
        dropout_rate: spec.dropout_rate,
        layer_norm: &Layers.rms_norm(&1, name: &2, epsilon: spec.layer_norm_epsilon),
        ffn: &ffn(&1, spec, name: &2),
        block_type: :norm_first,
        attention_head_size: spec.attention_head_size,
        output_hidden_states: spec.output_hidden_states,
        output_attentions: spec.output_attentions,
        query_use_bias: false,
        key_use_bias: false,
        value_use_bias: false,
        output_use_bias: false,
        attention_relative_bias: [
          bidirectional: true,
          num_buckets: spec.relative_attention_num_buckets,
          max_distance: spec.relative_attention_max_distance
        ],
        share_attention_relative_bias: true,
        scale_query?: false,
        name: join(name, "blocks")
      )

    hidden_state =
      encoder_outputs.hidden_state
      |> Layers.rms_norm(epsilon: spec.layer_norm_epsilon, name: join(name, "output_norm"))
      |> Axon.dropout(rate: spec.dropout_rate)

    %{
      hidden_state: hidden_state,
      hidden_states: Layers.replace(encoder_outputs.hidden_states, -1, hidden_state),
      attentions: encoder_outputs.attentions
    }
  end

  defp decoder(
         hidden_state,
         attention_mask,
         attention_head_mask,
         encoder_hidden_state,
         encoder_attention_mask,
         cross_attention_head_mask,
         cache,
         spec,
         opts
       ) do
    name = opts[:name]

    decoder_outputs =
      Layers.Transformer.blocks(hidden_state,
        attention_mask: attention_mask,
        attention_head_mask: attention_head_mask,
        cross_hidden_state: encoder_hidden_state,
        cross_attention_mask: encoder_attention_mask,
        cross_attention_head_mask: cross_attention_head_mask,
        cache: cache,
        causal?: true,
        num_blocks: spec.decoder_num_blocks,
        num_attention_heads: spec.decoder_num_attention_heads,
        hidden_size: spec.hidden_size,
        kernel_initializer: kernel_initializer(spec),
        dropout_rate: spec.dropout_rate,
        attention_head_size: spec.attention_head_size,
        layer_norm: &Layers.rms_norm(&1, name: &2, epsilon: spec.layer_norm_epsilon),
        ffn: &ffn(&1, spec, name: &2),
        block_type: :norm_first,
        output_hidden_states: spec.output_hidden_states,
        output_attentions: spec.output_attentions,
        query_use_bias: false,
        key_use_bias: false,
        value_use_bias: false,
        output_use_bias: false,
        attention_relative_bias: [
          bidirectional: false,
          num_buckets: spec.relative_attention_num_buckets,
          max_distance: spec.relative_attention_max_distance
        ],
        share_attention_relative_bias: true,
        scale_query?: false,
        name: join(name, "blocks")
      )

    hidden_state =
      decoder_outputs.hidden_state
      |> Layers.rms_norm(epsilon: spec.layer_norm_epsilon, name: join(name, "output_norm"))
      |> Axon.dropout(rate: spec.dropout_rate)

    %{
      cache: decoder_outputs.cache,
      hidden_state: hidden_state,
      hidden_states: Layers.replace(decoder_outputs.hidden_states, -1, hidden_state),
      attentions: decoder_outputs.attentions,
      cross_attentions: decoder_outputs.cross_attentions
    }
  end

  defp ffn(hidden_state, spec, opts) do
    name = opts[:name]

    intermediate =
      Axon.dense(hidden_state, spec.intermediate_size,
        name: join(name, "intermediate"),
        use_bias: false
      )

    hidden_state =
      if spec.ffn_gated_activation do
        gate =
          Axon.dense(hidden_state, spec.intermediate_size,
            name: join(name, "gate"),
            use_bias: false
          )

        Axon.multiply(intermediate, Layers.activation(gate, spec.activation))
      else
        Layers.activation(intermediate, spec.activation)
      end

    hidden_state
    |> Axon.dropout(rate: spec.dropout_rate)
    |> Axon.dense(spec.hidden_size, name: join(name, "output"), use_bias: false)
    |> Axon.dropout(rate: spec.dropout_rate)
  end

  defp language_modeling_head(hidden_state, spec, opts) do
    name = opts[:name]

    # TODO: Tie lm-head to word embedding as a spec option
    Layers.dense_transposed(hidden_state, spec.vocab_size,
      kernel_initializer: kernel_initializer(spec),
      name: join(name, "output")
    )
  end

  defp kernel_initializer(spec) do
    Axon.Initializers.normal(scale: spec.initializer_scale)
  end

  defimpl Bumblebee.HuggingFace.Transformers.Config do
    def load(spec, data) do
      import Shared.Converters

      opts =
        convert!(data,
          vocab_size: {"vocab_size", number()},
          tie_word_embeddings: {"tie_word_embeddings", boolean()},
          hidden_size: {"d_model", number()},
          attention_head_size: {"d_kv", number()},
          encoder_num_blocks: {"num_layers", number()},
          decoder_num_blocks: {"num_decoder_layers", number()},
          encoder_num_attention_heads: {"num_heads", number()},
          decoder_num_attention_heads: {"num_heads", number()},
          relative_attention_num_buckets: {"relative_attention_num_buckets", number()},
          relative_attention_max_distance: {"relative_attention_max_distance", number()},
          intermediate_size: {"d_ff", number()},
          activation: {"feed_forward_proj", activation()},
          ffn_gated_activation: {"feed_forward_proj", ffn_gated_activation()},
          dropout_rate: {"dropout", number()},
          initializer_scale: {"initializer_factor", number()}
        ) ++ Shared.common_options_from_transformers(data, spec)

      @for.config(spec, opts)
    end

    defp activation() do
      fn name, value ->
        try do
          case String.replace_prefix(value, "gated-", "") do
            # See https://github.com/huggingface/transformers/pull/17420
            "gelu" -> {:ok, :gelu_new}
            value -> {:ok, String.to_atom(value)}
          end
        rescue
          _error ->
            {:error, "unsupported value for #{inspect(name)}, got: #{inspect(value)}"}
        end
      end
    end

    defp ffn_gated_activation() do
      fn _name, value ->
        {:ok, String.starts_with?(value, "gated-")}
      end
    end
  end

  defimpl Bumblebee.HuggingFace.Transformers.Model do
    def params_mapping(spec) do
      %{
        # encoder
        "encoder_embedder.token_embedding" =>
          if(spec.tie_word_embeddings, do: "shared", else: "encoder.embed_tokens"),
        "encoder.blocks.{n}.self_attention_norm" => "encoder.block.{n}.layer.0.layer_norm",
        "encoder.blocks.{n}.self_attention.query" => "encoder.block.{n}.layer.0.SelfAttention.q",
        "encoder.blocks.{n}.self_attention.key" => "encoder.block.{n}.layer.0.SelfAttention.k",
        "encoder.blocks.{n}.self_attention.value" => "encoder.block.{n}.layer.0.SelfAttention.v",
        "encoder.blocks.{n}.self_attention.output" => "encoder.block.{n}.layer.0.SelfAttention.o",
        "encoder.blocks.0.self_attention.relative_attention_bias" =>
          "encoder.block.0.layer.0.SelfAttention.relative_attention_bias",
        "encoder.blocks.{n}.output_norm" => "encoder.block.{n}.layer.1.layer_norm",
        "encoder.blocks.{n}.ffn.gate" => "encoder.block.{n}.layer.1.DenseReluDense.wi_0",
        "encoder.blocks.{n}.ffn.intermediate" =>
          if(spec.ffn_gated_activation,
            do: "encoder.block.{n}.layer.1.DenseReluDense.wi_1",
            else: "encoder.block.{n}.layer.1.DenseReluDense.wi"
          ),
        "encoder.blocks.{n}.ffn.output" => "encoder.block.{n}.layer.1.DenseReluDense.wo",
        "encoder.output_norm" => "encoder.final_layer_norm",
        # decoder
        "decoder_embedder.token_embedding" =>
          if(spec.tie_word_embeddings, do: "shared", else: "decoder.embed_tokens"),
        "decoder.blocks.{n}.self_attention_norm" => "decoder.block.{n}.layer.0.layer_norm",
        "decoder.blocks.{n}.self_attention.query" => "decoder.block.{n}.layer.0.SelfAttention.q",
        "decoder.blocks.{n}.self_attention.key" => "decoder.block.{n}.layer.0.SelfAttention.k",
        "decoder.blocks.{n}.self_attention.value" => "decoder.block.{n}.layer.0.SelfAttention.v",
        "decoder.blocks.{n}.self_attention.output" => "decoder.block.{n}.layer.0.SelfAttention.o",
        "decoder.blocks.0.self_attention.relative_attention_bias" =>
          "decoder.block.0.layer.0.SelfAttention.relative_attention_bias",
        "decoder.blocks.{n}.cross_attention_norm" => "decoder.block.{n}.layer.1.layer_norm",
        "decoder.blocks.{n}.cross_attention.key" => "decoder.block.{n}.layer.1.EncDecAttention.k",
        "decoder.blocks.{n}.cross_attention.query" =>
          "decoder.block.{n}.layer.1.EncDecAttention.q",
        "decoder.blocks.{n}.cross_attention.value" =>
          "decoder.block.{n}.layer.1.EncDecAttention.v",
        "decoder.blocks.{n}.cross_attention.output" =>
          "decoder.block.{n}.layer.1.EncDecAttention.o",
        "decoder.blocks.{n}.output_norm" => "decoder.block.{n}.layer.2.layer_norm",
        "decoder.blocks.{n}.ffn.gate" => "decoder.block.{n}.layer.2.DenseReluDense.wi_0",
        "decoder.blocks.{n}.ffn.intermediate" =>
          if(spec.ffn_gated_activation,
            do: "decoder.block.{n}.layer.2.DenseReluDense.wi_1",
            else: "decoder.block.{n}.layer.2.DenseReluDense.wi"
          ),
        "decoder.blocks.{n}.ffn.output" => "decoder.block.{n}.layer.2.DenseReluDense.wo",
        "decoder.output_norm" => "decoder.final_layer_norm",
        # language modeling
        "language_modeling_head.output" =>
          if(spec.tie_word_embeddings, do: "shared", else: "lm_head")
      }
    end
  end
end
