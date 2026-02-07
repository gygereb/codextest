const canvas = document.getElementById('glcanvas');
const gl = canvas.getContext('webgl2');

if (!gl) {
  document.body.innerHTML = '<p style="padding:20px">WebGL2 is required.</p>';
  throw new Error('WebGL2 not supported');
}

const vertexSource = `#version 300 es
precision highp float;
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec3 aColor;

uniform mat4 uProjection;
uniform mat4 uView;

out vec3 vNormal;
out vec3 vColor;

void main() {
  vNormal = aNormal;
  vColor = aColor;
  gl_Position = uProjection * uView * vec4(aPosition, 1.0);
}
`;

const fragmentSource = `#version 300 es
precision highp float;

in vec3 vNormal;
in vec3 vColor;

uniform vec3 uLightDir;

out vec4 outColor;

void main() {
  float diff = max(dot(normalize(vNormal), normalize(uLightDir)), 0.0);
  vec3 color = vColor * diff;
  outColor = vec4(color, 1.0);
}
`;

function compileShader(type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader));
  }
  return shader;
}

function createProgram(vertexSrc, fragmentSrc) {
  const program = gl.createProgram();
  gl.attachShader(program, compileShader(gl.VERTEX_SHADER, vertexSrc));
  gl.attachShader(program, compileShader(gl.FRAGMENT_SHADER, fragmentSrc));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(program));
  }
  return program;
}

const program = createProgram(vertexSource, fragmentSource);
const uProjection = gl.getUniformLocation(program, 'uProjection');
const uView = gl.getUniformLocation(program, 'uView');
const uLightDir = gl.getUniformLocation(program, 'uLightDir');

const state = {
  keys: new Set(),
  yaw: -Math.PI / 4,
  pitch: -0.3,
  position: [20, 18, 28],
  lastTime: 0,
};

canvas.addEventListener('click', () => {
  canvas.requestPointerLock();
});

document.addEventListener('mousemove', (event) => {
  if (document.pointerLockElement !== canvas) return;
  const sensitivity = 0.002;
  state.yaw += event.movementX * sensitivity;
  state.pitch += event.movementY * sensitivity;
  const limit = Math.PI / 2 - 0.01;
  state.pitch = Math.max(-limit, Math.min(limit, state.pitch));
});

document.addEventListener('keydown', (event) => {
  state.keys.add(event.code);
});

document.addEventListener('keyup', (event) => {
  state.keys.delete(event.code);
});

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.floor(canvas.clientWidth * dpr);
  canvas.height = Math.floor(canvas.clientHeight * dpr);
  gl.viewport(0, 0, canvas.width, canvas.height);
}

window.addEventListener('resize', resize);
resize();

defineWasm().catch((err) => console.error(err));

async function defineWasm() {
  const wasmUrl = new URL('../bin/voxels.wasm', import.meta.url);
  const response = await fetch(wasmUrl);
  const { instance } = await WebAssembly.instantiateStreaming(response, {});

  const { memory, build_mesh, mesh_data_ptr, mesh_data_len } = instance.exports;
  build_mesh();

  const ptr = mesh_data_ptr();
  const len = mesh_data_len();
  const data = new Float32Array(memory.buffer, ptr, len);

  const vertexCount = len / 9;
  const vbo = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);

  const stride = 9 * 4;
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 3, gl.FLOAT, false, stride, 0);
  gl.enableVertexAttribArray(1);
  gl.vertexAttribPointer(1, 3, gl.FLOAT, false, stride, 3 * 4);
  gl.enableVertexAttribArray(2);
  gl.vertexAttribPointer(2, 3, gl.FLOAT, false, stride, 6 * 4);

  gl.enable(gl.DEPTH_TEST);
  gl.enable(gl.CULL_FACE);
  gl.cullFace(gl.BACK);
  gl.frontFace(gl.CCW);

  function frame(time) {
    const delta = Math.min((time - state.lastTime) / 1000, 0.05);
    state.lastTime = time;
    updateCamera(delta);
    render(vertexCount);
    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
}

function updateCamera(delta) {
  const speed = 8;
  const forward = [Math.cos(state.pitch) * Math.cos(state.yaw), Math.sin(state.pitch), Math.cos(state.pitch) * Math.sin(state.yaw)];
  const right = normalize(cross(forward, [0, 1, 0]));
  const up = [0, 1, 0];

  if (state.keys.has('KeyW')) {
    state.position = add(state.position, scale(forward, speed * delta));
  }
  if (state.keys.has('KeyS')) {
    state.position = add(state.position, scale(forward, -speed * delta));
  }
  if (state.keys.has('KeyA')) {
    state.position = add(state.position, scale(right, -speed * delta));
  }
  if (state.keys.has('KeyD')) {
    state.position = add(state.position, scale(right, speed * delta));
  }
  if (state.keys.has('Space')) {
    state.position = add(state.position, scale(up, speed * delta));
  }
  if (state.keys.has('ShiftLeft')) {
    state.position = add(state.position, scale(up, -speed * delta));
  }
}

function render(vertexCount) {
  gl.clearColor(0.05, 0.06, 0.08, 1.0);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

  const projection = mat4Perspective(Math.PI / 3, canvas.width / canvas.height, 0.1, 200.0);
  const forward = [Math.cos(state.pitch) * Math.cos(state.yaw), Math.sin(state.pitch), Math.cos(state.pitch) * Math.sin(state.yaw)];
  const center = add(state.position, forward);
  const view = mat4LookAt(state.position, center, [0, 1, 0]);

  gl.useProgram(program);
  gl.uniformMatrix4fv(uProjection, false, projection);
  gl.uniformMatrix4fv(uView, false, view);
  gl.uniform3fv(uLightDir, normalize([0.6, 1.0, 0.3]));

  gl.drawArrays(gl.TRIANGLES, 0, vertexCount);
}

function mat4Perspective(fovy, aspect, near, far) {
  const f = 1.0 / Math.tan(fovy / 2);
  const nf = 1 / (near - far);
  return new Float32Array([
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) * nf, -1,
    0, 0, (2 * far * near) * nf, 0,
  ]);
}

function mat4LookAt(eye, center, up) {
  const f = normalize(sub(center, eye));
  const s = normalize(cross(f, up));
  const u = cross(s, f);

  return new Float32Array([
    s[0], u[0], -f[0], 0,
    s[1], u[1], -f[1], 0,
    s[2], u[2], -f[2], 0,
    -dot(s, eye), -dot(u, eye), dot(f, eye), 1,
  ]);
}

function add(a, b) {
  return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
}

function sub(a, b) {
  return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
}

function scale(v, s) {
  return [v[0] * s, v[1] * s, v[2] * s];
}

function dot(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

function cross(a, b) {
  return [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
}

function normalize(v) {
  const len = Math.hypot(v[0], v[1], v[2]);
  if (len === 0) return [0, 0, 0];
  return [v[0] / len, v[1] / len, v[2] / len];
}
