import numpy as np, onnx
from onnx import helper, TensorProto, numpy_helper

rng = np.random.default_rng(0)
W1 = rng.standard_normal((16, 8)).astype(np.float32) * 0.3
b1 = np.zeros(16, np.float32)
W2 = rng.standard_normal((4, 16)).astype(np.float32) * 0.3
b2 = np.zeros(4, np.float32)

nodes = [
    helper.make_node("Gemm", ["input", "W1", "b1"], ["h1"], alpha=1.0, beta=1.0, transB=1),
    helper.make_node("Relu", ["h1"], ["a1"]),
    helper.make_node("Gemm", ["a1", "W2", "b2"], ["output"], alpha=1.0, beta=1.0, transB=1),
]
inits = [numpy_helper.from_array(t, n) for t, n in
         [(W1, "W1"), (b1, "b1"), (W2, "W2"), (b2, "b2")]]
graph = helper.make_graph(nodes, "mlp_smoke",
    [helper.make_tensor_value_info("input", TensorProto.FLOAT, [1, 8])],
    [helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, 4])], inits)
model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
model.ir_version = 8
onnx.checker.check_model(model)
onnx.save(model, "mlp_smoke.onnx")
print("mlp_smoke.onnx written, ir_version=8 opset=17")
