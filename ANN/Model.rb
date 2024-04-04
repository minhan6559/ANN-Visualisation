require_relative 'Activations'
require_relative 'Optimizers'
require 'numo/narray'
require 'rover-df'

# Artificial Neural Network class
class ANN
    attr_accessor :nodes_per_layer, :params, :activations, :batch_size, :learning_rate, :grads
    def initialize(nodes_per_layer, activations, batch_size = 64, learning_rate = 0.05)
        @nodes_per_layer = nodes_per_layer
        @activations = activations
        @params = initialize_params(nodes_per_layer)
        @batch_size = batch_size
        @learning_rate = learning_rate
        @grads = {}
    end
end

def initialize_params(nodes_per_layer)
    prev = 784
    params = {}
    nodes_per_layer.each_with_index do |cur, i|
        params["W#{i+1}"] = Numo::DFloat.new(cur, prev).rand_norm * Math.sqrt(2.0/prev)
        params["b#{i+1}"] = Numo::DFloat.zeros(cur, 1)
        prev = cur
    end
    return params
end

def single_layer_forward_propagation(a_prev, w, b, activation=Activation::RELU)
    z = w.dot(a_prev) + b
    case activation
    when Activation::SIGMOID
        a = sigmoid(z)
    when Activation::RELU
        a = relu(z)
    when Activation::TANH
        a = tanh(z)
    when Activation::SOFTPLUS
        a = softplus(z)
    when Activation::SOFTMAX
        a = softmax(z)
    else
        raise "Non-supported activation function"
    end
    return a, z
end

def forward_propagation(x, model)
    cache = {}
    a_cur = x

    model.nodes_per_layer.length.times do |i|
        layer_idx = i + 1
        a_prev = a_cur
        activation = model.activations[i]
        w = model.params["W#{layer_idx}"]
        b = model.params["b#{layer_idx}"]
        a_cur, z = single_layer_forward_propagation(a_prev, w, b, activation)
        cache["A#{i}"] = a_prev
        cache["Z#{layer_idx}"] = z
    end
    return a_cur, cache
end

def compute_cost(aL, y)
    m = y.shape[1].to_f
    return -(1.0/m) * (y * Numo::NMath.log(aL)).sum
end

def compute_accuracy(aL, y)
    _aL = aL.argmax(axis: 0)
    _y = y.argmax(axis: 0)
    return (_aL.eq(_y)).count.to_f / y.shape[1]
end

def single_layer_backward_propagation(dA_cur, w_cur, b_cur, z_cur, a_prev, activation=Activation::RELU)
    m = a_prev.shape[1].to_f
    case activation
    when Activation::SIGMOID
        dZ_cur = sigmoid_backward(dA_cur, z_cur)
    when Activation::RELU
        dZ_cur = relu_backward(dA_cur, z_cur)
    when Activation::TANH
        dZ_cur = tanh_backward(dA_cur, z_cur)
    when Activation::SOFTPLUS
        dZ_cur = softplus_backward(dA_cur, z_cur)
    when Activation::SOFTMAX
        dZ_cur = softmax_backward(dA_cur, z_cur)
    else
        raise "Non-supported activation function"
    end

    dW_cur = (1.0/m) * dZ_cur.dot(a_prev.transpose)
    db_cur = (1.0/m) * dZ_cur.sum(axis: 1, keepdims: true)
    dA_prev = w_cur.transpose.dot(dZ_cur)

    return dA_prev, dW_cur, db_cur
end

# softmax regression deep neural network backward propagation
def backward_propagation(aL, y, cache, model)
    dA_prev = aL - y
    l = model.nodes_per_layer.length

    (0...l).reverse_each do |layer_idx_prev|
        layer_idx_cur = layer_idx_prev + 1
        activ_function_cur = model.activations[layer_idx_prev]
        
        dA_cur = dA_prev
        
        a_prev = cache["A#{layer_idx_prev}"]
        z_cur = cache["Z#{layer_idx_cur}"]
        
        w_cur = model.params["W#{layer_idx_cur}"]
        b_cur = model.params["b#{layer_idx_cur}"]
        
        dA_prev, dW_cur, db_cur = single_layer_backward_propagation(
            dA_cur, w_cur, b_cur, z_cur, a_prev, activ_function_cur)
        
        model.grads["dW#{layer_idx_cur}"] = dW_cur
        model.grads["db#{layer_idx_cur}"] = db_cur
    end
end

def update_params_with_gd(model)
    model.nodes_per_layer.length.times do |i|
        layer_idx = i + 1
        model.params["W#{layer_idx}"] -= model.learning_rate * model.grads["dW#{layer_idx}"]
        model.params["b#{layer_idx}"] -= model.learning_rate * model.grads["db#{layer_idx}"]
    end
end

def train(x, y, model, epochs = 1000)
    m = x.shape[1]
    batch_size = model.batch_size

    epochs.times do |i|
        permutated_indexes = (0...m).to_a.shuffle
        shuffled_X = x[true, permutated_indexes].reshape(784, m)
        shuffled_Y = y[true, permutated_indexes].reshape(10, m)

        total_cost = 0
        num_complete_minibatches = (m / batch_size).to_i
        for k in 0...num_complete_minibatches
            mini_batch_X = shuffled_X[true, k * batch_size...(k+1) * batch_size]
            mini_batch_Y = shuffled_Y[true, k * batch_size...(k+1) * batch_size]

            aL, cache = forward_propagation(mini_batch_X, model)
            total_cost += compute_cost(aL, mini_batch_Y)
            backward_propagation(aL, mini_batch_Y, cache, model)
            update_params_with_gd(model)
        end

        if m % batch_size != 0
            mini_batch_X = shuffled_X[true, num_complete_minibatches * batch_size...m]
            mini_batch_Y = shuffled_Y[true, num_complete_minibatches * batch_size...m]

            aL, cache = forward_propagation(mini_batch_X, model)
            total_cost += compute_cost(aL, mini_batch_Y)
            backward_propagation(aL, mini_batch_Y, cache, model)
            update_params_with_gd(model)
        end
        
        avg_cost = total_cost / (num_complete_minibatches + (m % batch_size != 0 ? 1 : 0))

        if i % 1 == 0
            puts "Cost after iteration #{i}: #{avg_cost}"
            # puts "Accuracy after iteration #{i}: #{compute_accuracy(forward_propagation(x, model)[0], y)}"
        end
    end
    
end

def predict(x, model)
    aL = forward_propagation(x, model)[0]
    return aL.argmax
end

def save_model(model, model_name)
    fp = File.open("./saved_models/#{model_name}.bin", "wb")
    fp.write(Marshal.dump(model))
    fp.close
end

def load_model(model_name)
    return Marshal.load(File.open("./saved_models/#{model_name}.bin", "rb"))
end

def load_dataset(dataset_name)
    dataset = Marshal.load(File.open("./dataset_bin/#{dataset_name}.bin", "rb"))
    return dataset
end

def max(*values)
    values.max
end

def min(*values)
    values.min
end

if __FILE__ == $0
    x_train = load_dataset("full_X_train")
    y_train = load_dataset("full_Y_train")
    
    model = ANN.new([128, 256, 10], [Activation::RELU, Activation::RELU, Activation::SOFTMAX], 64)
    
    train(x_train, y_train, model, 32)
    x_val = load_dataset("X_val")
    y_val = load_dataset("Y_val")

    puts "Accuracy: #{compute_accuracy(forward_propagation(x_val, model)[0], y_val)}"
    
    # save_model(model, "full_train_model_128_256")
end