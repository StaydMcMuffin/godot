/**************************************************************************/
/*  pipeline_cache_rd.h                                                   */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/os/spin_lock.h"
#include "servers/rendering/rendering_device.h"

/**
 * Pipeline versioning cache.
 *
 * Holds the shader, rendering state, and specialization constants shared by all `Version`s of the pipeline,
 * and manages the creation and freeing of said `Version`s' render pipelines.
 */
class PipelineCacheRD
{
private:
	SpinLock spin_lock;

	RID shader;  ///< `RID` of the `RD::Shader` used by this pipeline.

	RD::RenderPrimitive render_primitive;
	RD::PipelineRasterizationState rasterization_state;
	RD::PipelineMultisampleState multisample_state;
	RD::PipelineDepthStencilState depth_stencil_state;
	RD::PipelineColorBlendState blend_state;
	int dynamic_state_flags = 0;
	Vector<RD::PipelineSpecializationConstant> base_specialization_constants;

	/**
	 * Pipeline `Version` configuration struct.
	 *
	 * Holds rendering parameters that quantify a unique `Version` of the base pipeline, as well as the `RID` of said `Version`'s compiled render pipeline.
	 */
	struct Version
	{
		RD::VertexFormatID vertex_id;
		RD::FramebufferFormatID framebuffer_id;
		uint32_t render_pass;
		bool wireframe;
		uint32_t bool_specializations;
		RID pipeline;
	};

	// TODO: Is there uh, any reason for this to be a C-style array and not a Vector? :V
	Version *versions = nullptr;  
	uint32_t version_count;

	/** Create and cache a new `Version` of this pipeline matching the given configuration parameters.
	 * \retval pipeline `RID` of the created render pipeline. */
	RID _generate_version (
			RD::VertexFormatID p_vertex_format_id,
			RD::FramebufferFormatID p_framebuffer_format_id,
			bool p_wireframe,
			uint32_t p_render_pass,
			uint32_t p_bool_specializations
	);

	/** Free all cached `Versions` of this pipeline. */
	void _clear();

public:
	/**
	 * Initialize this pipeline with the supplied shader, rendering state, and specialization constants.
	 *
	 * This necessarily clears the entire cache for this pipeline; existing `Version`s will not be recompiled until they are requested again via `get_render_pipeline`.
	 */
	void setup (
			RID p_shader,
			RD::RenderPrimitive p_primitive,
	  const	RD::PipelineRasterizationState &p_rasterization_state,
			RD::PipelineMultisampleState p_multisample,
	  const	RD::PipelineDepthStencilState &p_depth_stencil_state,
	  const	RD::PipelineColorBlendState &p_blend_state,
			int p_dynamic_state_flags = 0,
	  const	Vector<RD::PipelineSpecializationConstant> &p_base_specialization_constants = Vector<RD::PipelineSpecializationConstant>()
	);

	/**
	 * Re-initialize this pipeline with the supplied shader, keeping its existing rendering state and specialization constants.
	 *
	 * This necessarily clears the entire cache for this pipeline; existing `Version`s will not be recompiled until they are requested again via `get_render_pipeline`.
	 * @note Does nothing if the provided \a p_shader matches the existing \p shader .
	 */
	void update_shader(RID p_shader);
	
	/**
	 * Re-initialize this pipeline with the supplied specialization constants, keeping its existing shader and rendering state.
	 *
	 * This necessarily clears the entire cache for this pipeline; existing `Version`s will not be recompiled until they are requested again via `get_render_pipeline`.
	 * @note Does nothing if the provided \a p_base_specialization_constants match the existing \p base_specialization_constants .
	 */
	void update_specialization_constants (
	  const	Vector<RD::PipelineSpecializationConstant> &p_base_specialization_constants
	);

	/**
	 * Retrieve a cached `Version` of this pipeline matching the given configuration parameters, or generate a new `Version` if none exists.
	 */
	_FORCE_INLINE_
	RID get_render_pipeline (
			RD::VertexFormatID p_vertex_format_id,
			RD::FramebufferFormatID p_framebuffer_format_id,
			bool p_wireframe = false,
			uint32_t p_render_pass = 0,
			uint32_t p_bool_specializations = 0
		)
	{
#ifdef DEBUG_ENABLED
		ERR_FAIL_COND_V_MSG(shader.is_null(), RID(),
				"Attempted to use an unused shader variant (shader is null),");
#endif // DEBUG_ENABLED
		spin_lock.lock();
		p_wireframe |= rasterization_state.wireframe;

		// Search for matching configuration in existing pipeline versions.
		RID result;
		for (uint32_t i = 0; i < version_count; i++)
		{
			if (versions[i].vertex_id == p_vertex_format_id
			 && versions[i].framebuffer_id == p_framebuffer_format_id
			 && versions[i].wireframe == p_wireframe
			 && versions[i].render_pass == p_render_pass
			 && versions[i].bool_specializations == p_bool_specializations
				)
			{
				// Matching version already exists, return its RID.
				result = versions[i].pipeline;
				spin_lock.unlock();
				return result;
			}
		}

		// No matching version found, generate a new one.
		result = _generate_version(p_vertex_format_id, p_framebuffer_format_id, p_wireframe, p_render_pass, p_bool_specializations);
		spin_lock.unlock();
		return result;
	}

	/** Retrieve the \p vertex_input_mask parameter of the \p shader used by this pipeline. */
	_FORCE_INLINE_
	uint64_t get_vertex_input_mask()
	{
		ERR_FAIL_COND_V(shader.is_null(), 0);
		return RD::get_singleton()->shader_get_vertex_input_attribute_mask(shader);
	}

	/** Free all cached `Version`s of this pipeline, and unset its \p shader . */
	void clear();
	
	PipelineCacheRD();
	~PipelineCacheRD();
};
