import tables
import sequtils
import strutils
import math, random
import opengl

import nimx.view
import nimx.image
import nimx.context
import nimx.animation
import nimx.window
import nimx.timer
import nimx.portable_gl

import rod.scene_composition
import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.sprite
import rod.component.particle_emitter
import rod.component.visual_modifier
import rod.component.mesh_component
import rod.component.material
import rod.component.particle_system
import rod.animated_image

import utils.pause
import utils.helpers

import soft_billboard

import core.slot.base_slot_machine_view

type InstanceMesh* = ref object of MeshComponent

type InstanceCloud* = ref object of MeshComponent

method init*(m: InstanceMesh) =
    m.bProccesPostEffects = true
    m.material = newDefaultMaterial()
    m.prevTransform.loadIdentity()
    m.vboData.new()
    m.vboData.minCoord = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
    m.vboData.maxCoord = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)
    m.debugSkeleton = false
    procCall m.Component.init()

method draw*(m: InstanceMesh) =
    let c = currentContext()
    let gl = c.gl

    gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)

    if m.material.shader == invalidProgram:
        m.material.useManualShaderComposing = false

    m.material.setupVertexAttributes(m.vboData.vertInfo)
    m.material.updateSetup(m.node)

    if m.material.bEnableBackfaceCulling:
        gl.enable(gl.CULL_FACE)

    var vpm = m.node.sceneView.getViewProjectionMatrix()

    for n in m.node.children:
        if n.alpha > 0:
            var mvp = vpm * n.worldTransform()
            gl.uniformMatrix4fv(gl.getUniformLocation(m.material.shader, "modelViewProjectionMatrix"), false, mvp)
            gl.drawElements(gl.TRIANGLES, m.vboData.numberOfIndices, gl.UNSIGNED_SHORT)

    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(gl.FRONT_AND_BACK, GL_FILL)

    #TODO to default settings
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.disable(gl.DEPTH_TEST)
    gl.activeTexture(gl.TEXTURE0)
    gl.enable(gl.BLEND)

method draw*(m: InstanceCloud) =
    let c = currentContext()
    let gl = c.gl

    gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)

    if m.material.shader == invalidProgram:
        m.material.useManualShaderComposing = false

    m.material.setupVertexAttributes(m.vboData.vertInfo)
    m.material.updateSetup(m.node)

    if m.material.bEnableBackfaceCulling:
        gl.enable(gl.CULL_FACE)

    var vpm = m.node.sceneView.getViewProjectionMatrix()

    for n in m.node.children:
        if n.alpha > 0:
            var mvp = vpm * n.worldTransform()
            gl.uniformMatrix4fv(gl.getUniformLocation(m.material.shader, "modelViewProjectionMatrix"), false, mvp)

            let mesh = n.componentIfAvailable(MeshComponent)
            if not mesh.isNil:
                let mat = mesh.material
                if not mat.albedoTexture.isNil and mat.albedoTexture.isLoaded:
                    var theQuad {.noinit.}: array[4, GLfloat]
                    gl.activeTexture(GLenum(gl.TEXTURE0))
                    gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(mat.albedoTexture, gl, theQuad))
                    gl.uniform4fv(gl.getUniformLocation(m.material.shader, "uTexUnitCoords"), theQuad)
                    # gl.uniform1i(gl.getUniformLocation(m.material.shader, "texUnit"), 0.GLint)
                    # gl.uniform1f(gl.getUniformLocation(m.material.shader, "uTexUnitPercent"), mat.albedoPercent)
            gl.drawElements(gl.TRIANGLES, m.vboData.numberOfIndices, gl.UNSIGNED_SHORT)

    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(gl.FRONT_AND_BACK, GL_FILL)

    #TODO to default settings
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.disable(gl.DEPTH_TEST)
    gl.activeTexture(gl.TEXTURE0)
    gl.enable(gl.BLEND)

method isPosteffectComponent*(m: InstanceCloud): bool = true
method isPosteffectComponent*(m: InstanceMesh): bool = true

registerComponent(InstanceMesh)
registerComponent(InstanceCloud)
