import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const zero = process.env.ZERO_BIN
  ? resolve(process.env.ZERO_BIN)
  : fileURLToPath(new URL('../../../bin/zero', import.meta.url))
const identifier = /^[A-Za-z_][A-Za-z0-9_]*$/u
const integerLiteral = /^-?[0-9]{1,19}(?:_i64)?$/u

function matches(value, pattern) {
  return typeof value === 'string' && value === value.trim() && pattern.test(value)
}

function inspectBinding(project, path) {
  const binding = JSON.parse(readFileSync(path, 'utf8'))
  if (binding?.schemaVersion !== 1 || binding.target !== 'linux-x64' ||
      binding.effects !== 'foreign' || binding.abiSymbol !== 'zerox_go_add' ||
      binding.abiType !== 'int64_t' || binding.result !== 'int64' ||
      !Array.isArray(binding.parameters) || binding.parameters.length !== 2 ||
      binding.parameters.some(type => type !== 'int64')) {
    throw new Error('Expected a ZeroX v1 foreign int64 binding for linux-x64')
  }
  for (const field of ['package', 'module', 'moduleVersion', 'goSymbol']) {
    if (typeof binding[field] !== 'string' || !binding[field].trim()) {
      throw new Error(`Missing binding field: ${field}`)
    }
  }

  const inspection = JSON.parse(execFileSync(zero, [
    'inspect', '--json', '--target', binding.target, '.',
  ], { cwd: project, encoding: 'utf8' }))
  const graphHash = inspection.graph?.graphHash
  if (resolve(project, inspection.graph?.artifact ?? '') !== resolve(project, 'zero.graph') ||
      !matches(graphHash, /^graph:[0-9a-f]{16}$/u)) {
    throw new Error('Expected a repository graph at zero.graph')
  }
  const imports = (inspection.cImports ?? []).filter(entry => entry.header === 'abi/zerox_go.h')
  if (imports.length !== 1 || !matches(imports[0].alias, identifier)) {
    throw new Error('Expected one C import of abi/zerox_go.h in the Zero graph')
  }
  const { alias, typedModel } = imports[0]
  const fn = typedModel?.functions?.find(entry => entry.name === binding.abiSymbol)
  if (fn?.returnType !== binding.abiType || fn.params.length !== 2 ||
      fn.params.some(param => param.type !== binding.abiType)) {
    throw new Error('The Zero C import signature differs from the Go binding')
  }

  return {
    symbol: { ...binding, graphHash, callee: `${alias}.${fn.name}`, requiresForeignConsent: true },
    functions: inspection.functions,
  }
}

function callArgument(value, index, parameters) {
  if (matches(value, integerLiteral)) {
    const number = BigInt(value.replace(/_i64$/u, ''))
    if (number < -(2n ** 63n) || number >= 2n ** 63n) {
      throw new Error(`Argument ${index} is outside the i64 range`)
    }
    return `${number}_i64`
  }
  if (matches(value, identifier) && parameters.some(param => param.name === value && param.type === 'i64')) {
    return value
  }
  throw new Error(`Argument ${index} (${value}) must be an i64 parameter or a signed i64 integer literal`)
}

function main([command, projectPath, metadata, ...args]) {
  if (!projectPath || !metadata || !['discover', 'plan'].includes(command) ||
      (command === 'discover' ? args.length !== 0 : ![4, 5].includes(args.length))) {
    throw new Error('Usage: zerox-go.mjs discover PROJECT BINDING | plan PROJECT BINDING GRAPH_HASH FUNCTION LEFT RIGHT --allow-foreign')
  }
  const project = resolve(projectPath)
  if (command === 'discover') {
    console.log(JSON.stringify(inspectBinding(project, metadata).symbol, null, 2))
    return
  }

  const [graphHash, fn, left, right, consent] = args
  if (consent !== '--allow-foreign') {
    throw new Error('Planning a Go call requires --allow-foreign')
  }
  if (!matches(graphHash, /^graph:[0-9a-f]{16}$/u) || !matches(fn, identifier)) {
    throw new Error('Expected a graph hash and a function name')
  }
  const { symbol, functions } = inspectBinding(project, metadata)
  const destinations = functions.filter(entry => entry.name === fn)
  const destination = destinations[0]
  if (destinations.length !== 1 || destination.returnType !== 'i64' ||
      destination.generic || destination.raises) {
    throw new Error('Expected one non-generic, non-raising destination function returning i64')
  }
  const parameters = destination.ownership.params
  const leftArg = callArgument(left, 1, parameters)
  const rightArg = callArgument(right, 2, parameters)
  const patch = [
    'zero-program-graph-patch v1',
    `expect graphHash "${graphHash}"`,
    `replaceFunctionBody ${fn}`,
    `  return ${symbol.callee}(${leftArg}, ${rightArg})`,
    'end',
    '',
  ].join('\n')
  execFileSync(zero, [
    'patch', '--json', '--check-only', '.', '--patch-text', patch,
  ], { cwd: project, encoding: 'utf8' })
  process.stdout.write(patch)
}

try {
  main(process.argv.slice(2))
} catch (error) {
  if (error.stdout || error.stderr) {
    process.stderr.write(error.stdout || error.stderr)
  } else {
    console.error(error.message)
  }
  process.exitCode = 1
}
