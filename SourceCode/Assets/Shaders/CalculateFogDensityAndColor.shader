Shader "Custom/CalculateFogDensityAndColor"
{
	Properties
	{
		_MainTex("", any) = "" {}	// The main texture to be calculated
	}

	CGINCLUDE
	#include "UnityCG.cginc"
	#include "UnityDeferredLibrary.cginc"
	#include "noiseSimplex.cginc"


	/**********************************************************************************************
	*                                   SHADER VARIANTS
	**********************************************************************************************/
	
	#pragma shader_feature __ RANDOMIZED_EVALUATION_POSITION
	#pragma shader_feature __ USE_GLOBAL_XYZ
	#pragma shader_feature __ INFINITE_FOG
	#pragma shader_feature __ MULTIPLE_LIGHTS
	#pragma shader_feature __ HEIGHT_DENSITY_FALLOFF
	#pragma shader_feature __ EXPONENTIAL_HEIGHT_DENSITY_FALLOFF
	#pragma shader_feature __ EDGE_DENSITY_FALLOFF
	#pragma shader_feature __ EXPONENTIAL_EDGE_DENSITY_FALLOFF
	#pragma shader_feature __ FOG_SHADOWS
	#pragma shader_feature __ AMBIENT_FOG
	#pragma shader_feature __ NOISY_FOG
	#pragma shader_feature __ ADDITIVE_NOISE



	/**********************************************************************************************
	*                                     VARIABLES
	**********************************************************************************************/
	
	// Use the globally-declared shadow map	
	UNITY_DECLARE_SHADOWMAP(ShadowMap);

	// Textures to sample
	uniform sampler2D _MainTex;
	uniform sampler2D _RandomNoiseTex;

	// Texture dimensions
	uniform float4 _MainTex_TexelSize;
	uniform float4 _CameraDepthTexture_TexelSize;

	// Fog volume
	uniform float3 _FogWorldPosition;
	uniform float3 _FogDimensions;
	uniform float3 _FogUp;
	uniform float3 _FogForward;
	uniform float3 _FogRight;

	// Fog volume CGs and normals
	uniform float3 _LeftCG;
	uniform float3 _LeftNormal;
	uniform float3 _RightCG;
	uniform float3 _RightNormal;
	uniform float3 _FrontCG;
	uniform float3 _FrontNormal;
	uniform float3 _BackCG;
	uniform float3 _BackNormal;
	uniform float3 _TopCG;
	uniform float3 _TopNormal;
	uniform float3 _BottomCG;
	uniform float3 _BottomNormal;

	// Lighting
	uniform float  _DirectionalLightIntensity = 0;
	uniform float3 _DirectionalLightDirection = float3(0, 0, 0);
	uniform float3 _DirectionalLightRGBColor = float3(0, 0, 0);
	uniform float  _PointLightIntensity = 0;
	uniform float3 _PointLightRGBColor = float3(0, 0, 0);
	uniform float3 _PointLightLocation = float3(0, 0, 0);
	uniform float  _PointLightRange = 0;
	uniform float _ConstantAttenuation = 0.1f;
	uniform float _LinearAttenuation = 0.00005f;
	uniform float _ExponentialAttenuation = 0.0005f;
	uniform float3 _AmbientFogRGBColor;

	// Physical Values
	uniform float _ShadowStrength;			// Knockdown on the light when in shadows
	uniform float _AmbientLitFog;			// Used to bleed some lit fog into shadowed areas
	uniform float _DistanceToFogSaturation;	// Max. Distance until pixel is saturated with fog color
	uniform float _HeightToStartFalloffAt;	// Bottom edge altitude of fog density falloff in y direction
	uniform float _YFalloffDistance;		// Distance to perform y density falloff over
	uniform float _FogEdgeFalloffInX = 0;	// Used to fade out the fog at the x edge of the volume
	uniform float _FogEdgeFalloffInZ = 0;	// Used to fade out the fog at the z edge of the volume

	// Fog Noise
	uniform float _NoiseStrength;			// Influence of simplex noise on fog density
	uniform float _NoiseSize;				// Used to scale the size of the noise artifacts
	uniform float3 _NoiseVelocity;			// Movement of fog noise over time

	// Camera transforms
	uniform float4x4 _InverseViewMatrix;		// Camera-to-World matrix
	uniform float4x4 _InverseProjectionMatrix;	// Inverse of the current camera matrix

	// Other camera data
	uniform float _FarClipPlane;			// The camera's far clipping plane distance

	// Max number of steps per pixel
	int _RaymarchSteps;						// Number of steps to evaluate pixel values in fog



	/**********************************************************************************************
	*                                     CONSTANTS
	**********************************************************************************************/

	#define e 2.71828
	#define pi 3.14159
	#define	SMALL_NUMBER 0.000001



	/**********************************************************************************************
	*                                  MISC. FUNCTIONS
	**********************************************************************************************/

	float4 NearestEdgeDistancesInFogBox(float3 evaluationPoint)
	{
		float3 distancesFromFogCG = (evaluationPoint - _FogWorldPosition);
#if !defined(USE_GLOBAL_XYZ)
		// Need to transform the distanceToFogCG into local coordinates
		float3 locationRelativeToFogCG = distancesFromFogCG;
		distancesFromFogCG.x = dot(locationRelativeToFogCG, _FogRight);
		distancesFromFogCG.y = dot(locationRelativeToFogCG, _FogUp);
		distancesFromFogCG.z = dot(locationRelativeToFogCG, _FogForward);
#endif
		float3 distancesFromNearestFogVolumeEdges = abs(distancesFromFogCG) - (_FogDimensions / 2.0f);
		if (distancesFromNearestFogVolumeEdges.x <= 0.0f &&
			distancesFromNearestFogVolumeEdges.y <= 0.0f &&
			distancesFromNearestFogVolumeEdges.z <= 0.0f)
		{
			return float4(distancesFromNearestFogVolumeEdges, 1.0f);
		}
		return float4(distancesFromNearestFogVolumeEdges, 0.0f);
	}

	float4 GetUnityShadowCascadeWeights(float evaluationDepthInScene)
	{
		float4 ShadowCascadeNearPlane = float4(evaluationDepthInScene >= _LightSplitsNear);
		float4 ShadowCascadeFarPlane = float4(evaluationDepthInScene < _LightSplitsFar);

		return ShadowCascadeNearPlane * ShadowCascadeFarPlane;
	}

	float4 GetUnityShadowMapCoordinates(float4 locationWorldSpace, float4 shadowCascadeWeights)
	{
		float3 shadowMapCoordinates = float3(0, 0, 0);

		if (shadowCascadeWeights[0] == 1)
		{
			shadowMapCoordinates += mul(unity_WorldToShadow[0], locationWorldSpace).xyz;
		}
		else if (shadowCascadeWeights[1] == 1)
		{
			shadowMapCoordinates += mul(unity_WorldToShadow[1], locationWorldSpace).xyz;
		}
		else if (shadowCascadeWeights[2] == 1)
		{
			shadowMapCoordinates += mul(unity_WorldToShadow[2], locationWorldSpace).xyz;
		}
		else if (shadowCascadeWeights[3] == 1)
		{
			shadowMapCoordinates += mul(unity_WorldToShadow[3], locationWorldSpace).xyz;
		}

		return float4(shadowMapCoordinates, 1);
	}

	float FogHeightDensity(float3 evaluationPoint)
	{
		float heightFactor = 1.0;
		float heightDensityKnockdown = 1.0f;
#if defined(INFINITE_FOG) && defined(EXPONENTIAL_HEIGHT_DENSITY_FALLOFF)
		// Exponential Falloff, _HeightToStartFalloffAt is relative to (0,0,0)
		heightFactor = 7.5f / _YFalloffDistance;
		heightDensityKnockdown = pow(e, (-(evaluationPoint.y - _HeightToStartFalloffAt) * heightFactor));
#elif defined(INFINITE_FOG) && !defined(EXPONENTIAL_HEIGHT_DENSITY_FALLOFF)
		// Linear falloff, _HeightToStartFalloffAt is relative to (0,0,0) 
		heightFactor = 1.0f / _YFalloffDistance;
		heightDensityKnockdown = 1.0f - (evaluationPoint.y - _HeightToStartFalloffAt) * heightFactor;
#elif !defined(INFINITE_FOG) && defined(EXPONENTIAL_HEIGHT_DENSITY_FALLOFF)
		// _HeightToStartFalloffAt is relative to bottom of fog volume
		float3 FogUpNormalVector = _FogUp / dot(_FogUp, _FogUp);
		float3 CenterOfFogBottom = _FogWorldPosition - (FogUpNormalVector * (_FogDimensions.y / 2.0));
		float3 CenterOfFogTop = _FogWorldPosition + (FogUpNormalVector * (_FogDimensions.y / 2.0));
		float3 EvaluationPointVectorFromBottom = evaluationPoint - CenterOfFogBottom;

		// Calculate the falloff start point along the FogUpNormalVector
		float3 startOfFalloff = CenterOfFogBottom + _HeightToStartFalloffAt * FogUpNormalVector;

		// Calculate distance to top of fog volume from evaluation point
		float heightRemainingForDensityFalloff = _FogDimensions.y - dot(EvaluationPointVectorFromBottom, FogUpNormalVector);

		// Make sure the requested falloff distance is within fog volume, 
		// otherwise calculate a new distance
		if (heightRemainingForDensityFalloff > 0)
		{
			if (_YFalloffDistance > (heightRemainingForDensityFalloff))
			{
				_YFalloffDistance = heightRemainingForDensityFalloff;
			}
		}
		else
		{
			return 1;	// No knockdown
		}

		heightFactor = 7.5f / _YFalloffDistance;

		float evaluationHeightRelativeToFogBottom = dot(EvaluationPointVectorFromBottom, FogUpNormalVector);
		heightDensityKnockdown = pow(e, (-(evaluationHeightRelativeToFogBottom - _HeightToStartFalloffAt) * heightFactor));
		
#elif !defined(INFINITE_FOG) && !defined(EXPONENTIAL_HEIGHT_DENSITY_FALLOFF)
		// _HeightToStartFalloffAt is relative to bottom of fog volume
		float3 FogUpNormalVector = _FogUp / dot(_FogUp, _FogUp);
		float3 CenterOfFogBottom = _FogWorldPosition - (FogUpNormalVector * (_FogDimensions.y / 2.0));
		float3 CenterOfFogTop = _FogWorldPosition + (FogUpNormalVector * (_FogDimensions.y / 2.0));
		float3 EvaluationPointVectorFromBottom = evaluationPoint - CenterOfFogBottom;

		// Calculate the falloff start point along the FogUpNormalVector
		float3 startOfFalloff = CenterOfFogBottom + _HeightToStartFalloffAt * FogUpNormalVector;

		// Calculate distance to top of fog volume from evaluation point
		float heightRemainingForDensityFalloff = _FogDimensions.y - dot(EvaluationPointVectorFromBottom, FogUpNormalVector);

		// Make sure the requested falloff distance is within fog volume, 
		// otherwise calculate a new distance
		if (heightRemainingForDensityFalloff > 0)
		{
			if (_YFalloffDistance > (heightRemainingForDensityFalloff))
			{
				_YFalloffDistance = heightRemainingForDensityFalloff;
			}
		}
		else
		{
			return 1;	// No knockdown
		}

		heightFactor = 1.0f / _YFalloffDistance;

		float evaluationHeightRelativeToFogBottom = dot(EvaluationPointVectorFromBottom, FogUpNormalVector);
		heightDensityKnockdown = 1.0f - (evaluationHeightRelativeToFogBottom - _HeightToStartFalloffAt) * heightFactor;
#else
		heightDensityKnockdown = 0.0f;
#endif

		if (heightDensityKnockdown > 1) // happens when evaluationHeight is below _HeightToStartFalloffAt
		{
			heightDensityKnockdown = 1;
		}
		else if (heightDensityKnockdown < 0.00005)
		{
			heightDensityKnockdown = 0;
		}

		return heightDensityKnockdown;
	}

	float FogEdgeDensityXZ(float4 distanceToNearestFogEdges)
	{
		float densityKnockdownFactor = 1.00f;
		float percentDistanceInXFromCG = abs(distanceToNearestFogEdges.x / (_FogDimensions.x / 2.0f));
		float percentDistanceInZFromCG = abs(distanceToNearestFogEdges.z / (_FogDimensions.z / 2.0f));
#if defined(EXPONENTIAL_EDGE_DENSITY_FALLOFF)
		if (_FogEdgeFalloffInX > 0 && percentDistanceInXFromCG < _FogEdgeFalloffInX)
		{
			densityKnockdownFactor *= pow(e, (lerp(-10, 0, percentDistanceInXFromCG / _FogEdgeFalloffInX)));
		}

		if (_FogEdgeFalloffInZ > 0 && percentDistanceInZFromCG < _FogEdgeFalloffInZ)
		{
			densityKnockdownFactor *= pow(e, (lerp(-10, 0, percentDistanceInZFromCG / _FogEdgeFalloffInZ)));
		}
#else	
		// Linear falloff
		if (_FogEdgeFalloffInX > 0 && percentDistanceInXFromCG < _FogEdgeFalloffInX)
		{
			densityKnockdownFactor *= lerp(0, 1, percentDistanceInXFromCG / _FogEdgeFalloffInX);
		}

		if (_FogEdgeFalloffInZ > 0 && percentDistanceInZFromCG < _FogEdgeFalloffInZ)
		{
			densityKnockdownFactor *= lerp(0, 1, percentDistanceInZFromCG / _FogEdgeFalloffInZ);
		}
#endif
		if (densityKnockdownFactor < 0.00005)
		{
			densityKnockdownFactor = 0.0f;
		}
		return densityKnockdownFactor;
	}

	float4 DetermineLeftFaceInterceptPoint(float3 evaluationPoint)
	{
		// REFERENCE: http://www.geomalgorithms.com/a05-_intersect-1.html

		float3 cameraToEvaluationPoint = evaluationPoint - _WorldSpaceCameraPos.xyz;
		float3 planeToCameraPosition = _WorldSpaceCameraPos.xyz - _LeftCG;

		float planeDotVector1 = dot(_LeftNormal, cameraToEvaluationPoint);
		float nPlaneDotVector2 = -dot(_LeftNormal, planeToCameraPosition);

		float4 InterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);	// Intercept.w = 0 --> No intercept

		if (abs(planeDotVector1) < SMALL_NUMBER)
		{
			// Vector is parallel to plane; ignore intercept (could lie in plane...)
		}
		else
		{
			// Check for intercept
			float sI = nPlaneDotVector2 / planeDotVector1;
			if (sI >= 0.0f && sI <= 1.0f)
			{
				InterceptLocation.xyz = _WorldSpaceCameraPos.xyz + sI * cameraToEvaluationPoint;
				InterceptLocation.w = 1.0f;
			}
		}

		return InterceptLocation;
	}

	float4 DetermineRightFaceInterceptPoint(float3 evaluationPoint)
	{
		// REFERENCE: http://www.geomalgorithms.com/a05-_intersect-1.html

		float3 cameraToEvaluationPoint = evaluationPoint - _WorldSpaceCameraPos.xyz;
		float3 planeToCameraPosition = _WorldSpaceCameraPos.xyz - _RightCG;

		float planeDotVector1 = dot(_RightNormal, cameraToEvaluationPoint);
		float nPlaneDotVector2 = -dot(_RightNormal, planeToCameraPosition);

		float4 InterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);	// Intercept.w = 0 --> No intercept

		if (abs(planeDotVector1) < SMALL_NUMBER)
		{
			// Vector is parallel to plane; ignore intercept (could lie in plane...)
		}
		else
		{
			// Check for intercept
			float sI = nPlaneDotVector2 / planeDotVector1;
			if (sI >= 0.0f && sI <= 1.0f)
			{
				InterceptLocation.xyz = _WorldSpaceCameraPos.xyz + sI * cameraToEvaluationPoint;
				InterceptLocation.w = 1.0f;
			}
		}

		return InterceptLocation;
	}

	float4 DetermineFrontFaceInterceptPoint(float3 evaluationPoint)
	{
		// REFERENCE: http://www.geomalgorithms.com/a05-_intersect-1.html

		float3 cameraToEvaluationPoint = evaluationPoint - _WorldSpaceCameraPos.xyz;
		float3 planeToCameraPosition = _WorldSpaceCameraPos.xyz - _FrontCG;

		float planeDotVector1 = dot(_FrontNormal, cameraToEvaluationPoint);
		float nPlaneDotVector2 = -dot(_FrontNormal, planeToCameraPosition);

		float4 InterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);	// Intercept.w = 0 --> No intercept

		if (abs(planeDotVector1) < SMALL_NUMBER)
		{
			// Vector is parallel to plane; ignore intercept (could lie in plane...)
		}
		else
		{
			// Check for intercept
			float sI = nPlaneDotVector2 / planeDotVector1;
			if (sI >= 0.0f && sI <= 1.0f)
			{
				InterceptLocation.xyz = _WorldSpaceCameraPos.xyz + sI * cameraToEvaluationPoint;
				InterceptLocation.w = 1.0f;
			}
		}

		return InterceptLocation;
	}

	float4 DetermineBackFaceInterceptPoint(float3 evaluationPoint)
	{
		// REFERENCE: http://www.geomalgorithms.com/a05-_intersect-1.html

		float3 cameraToEvaluationPoint = evaluationPoint - _WorldSpaceCameraPos.xyz;
		float3 planeToCameraPosition = _WorldSpaceCameraPos.xyz - _BackCG;

		float planeDotVector1 = dot(_BackNormal, cameraToEvaluationPoint);
		float nPlaneDotVector2 = -dot(_BackNormal, planeToCameraPosition);

		float4 InterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);	// Intercept.w = 0 --> No intercept

		if (abs(planeDotVector1) < SMALL_NUMBER)
		{
			// Vector is parallel to plane; ignore intercept (could lie in plane...)
		}
		else
		{
			// Check for intercept
			float sI = nPlaneDotVector2 / planeDotVector1;
			if (sI >= 0.0f && sI <= 1.0f)
			{
				InterceptLocation.xyz = _WorldSpaceCameraPos.xyz + sI * cameraToEvaluationPoint;
				InterceptLocation.w = 1.0f;
			}
		}

		return InterceptLocation;
	}

	float4 DetermineTopFaceInterceptPoint(float3 evaluationPoint)
	{
		// REFERENCE: http://www.geomalgorithms.com/a05-_intersect-1.html

		float3 cameraToEvaluationPoint = evaluationPoint - _WorldSpaceCameraPos.xyz;
		float3 planeToCameraPosition = _WorldSpaceCameraPos.xyz - _TopCG;

		float planeDotVector1 = dot(_TopNormal, cameraToEvaluationPoint);
		float nPlaneDotVector2 = -dot(_TopNormal, planeToCameraPosition);

		float4 InterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);	// Intercept.w = 0 --> No intercept

		if (abs(planeDotVector1) < SMALL_NUMBER)
		{
			// Vector is parallel to plane; ignore intercept (could lie in plane...)
		}
		else
		{
			// Check for intercept
			float sI = nPlaneDotVector2 / planeDotVector1;
			if (sI >= 0.0f && sI <= 1.0f)
			{
				InterceptLocation.xyz = _WorldSpaceCameraPos.xyz + sI * cameraToEvaluationPoint;
				InterceptLocation.w = 1.0f;
			}
		}

		return InterceptLocation;
	}

	float4 DetermineBottomFaceInterceptPoint(float3 evaluationPoint)
	{
		// REFERENCE: http://www.geomalgorithms.com/a05-_intersect-1.html

		float3 cameraToEvaluationPoint = evaluationPoint - _WorldSpaceCameraPos.xyz;
		float3 planeToCameraPosition = _WorldSpaceCameraPos.xyz - _BottomCG;

		float planeDotVector1 = dot(_BottomNormal, cameraToEvaluationPoint);
		float nPlaneDotVector2 = -dot(_BottomNormal, planeToCameraPosition);

		float4 InterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);	// Intercept.w = 0 --> No intercept

		if (abs(planeDotVector1) < SMALL_NUMBER)
		{
			// Vector is parallel to plane; ignore intercept (could lie in plane...)
		}
		else
		{
			// Check for intercept
			float sI = nPlaneDotVector2 / planeDotVector1;
			if (sI >= 0.0f && sI <= 1.0f)
			{
				InterceptLocation.xyz = _WorldSpaceCameraPos.xyz + sI * cameraToEvaluationPoint;
				InterceptLocation.w = 1.0f;
			}
		}

		return InterceptLocation;
	}

	float4 DetermineInterceptPoint1(float3 evaluationPoint, float delta)
	{
		// Check intercept locations for all six planes
		float3 cameraToEvaluationPoint = normalize(evaluationPoint - _WorldSpaceCameraPos.xyz);
		float4 currentIntercept = float4(0.0f, 0.0f, 0.0f, 0.0f);

		float4 InterceptPoint = DetermineLeftFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint + delta * cameraToEvaluationPoint);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		InterceptPoint = DetermineRightFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint + delta * cameraToEvaluationPoint);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		InterceptPoint = DetermineFrontFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint + delta * cameraToEvaluationPoint);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		InterceptPoint = DetermineBackFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint + delta * cameraToEvaluationPoint);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		InterceptPoint = DetermineTopFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint + delta * cameraToEvaluationPoint);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		InterceptPoint = DetermineBottomFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint + delta * cameraToEvaluationPoint);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		return float4(0.0f, 0.0f, 0.0f, 0.0f);	// No intercepts with fog volume
	}

	float4 DetermineInterceptPoint2(float3 evaluationPoint, float delta)
	{
		// Check intercept locations for all six planes
		float3 cameraToEvaluationPointNormal = normalize(evaluationPoint - _WorldSpaceCameraPos.xyz);
		float4 currentIntercept = float4(0.0f, 0.0f, 0.0f, 0.0f);

		float4 InterceptPoint = DetermineLeftFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint - delta * cameraToEvaluationPointNormal);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		InterceptPoint = DetermineRightFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint - delta * cameraToEvaluationPointNormal);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}

		InterceptPoint = DetermineFrontFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint - delta * cameraToEvaluationPointNormal);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}
		
		InterceptPoint = DetermineBackFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint - delta * cameraToEvaluationPointNormal);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}
		
		InterceptPoint = DetermineTopFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint - delta * cameraToEvaluationPointNormal);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}
		
		InterceptPoint = DetermineBottomFaceInterceptPoint(evaluationPoint);
		if (InterceptPoint.w == 1.0f)
		{
			// Plane has an intercept point. Is it near box edge?
			currentIntercept = NearestEdgeDistancesInFogBox(InterceptPoint - delta * cameraToEvaluationPointNormal);

			if (currentIntercept.w == 1.0f)
			{
				// Success!
				return InterceptPoint;
			}
		}
	
		return float4(0.0f, 0.0f, 0.0f, 0.0f);	// No intercepts with fog volume
	}

	float DetermineClosestInterceptPoint(float3 point1, float3 point2)
	{
		float distance1 = length(point1 - _WorldSpaceCameraPos.xyz);
		float distance2 = length(point2 - _WorldSpaceCameraPos.xyz);

		if (distance1 <= distance2)
		{
			return 1.0f;
		}
		return 2.0f;
	}



	/**********************************************************************************************
	*                             MAIN SHADER FUNCTIONALITY
	**********************************************************************************************/

	struct v2f		// Vertex Data Structure
	{
		float4 pos : SV_POSITION;	// Vertex position in 3D scene coordinates
		float2 uv : TEXCOORD0;		// First uv coordinate
		float3 ray : TEXCOORD1;		// Second uv coordinate (used in raymarching)
	};

	v2f vert(appdata_img v)	// Vertex Shader - Determines the color of the vertices for each triangle
	{
		v2f o;									// Current vertex
		o.pos = UnityObjectToClipPos(v.vertex);	// World C.S. to Normalized C.S.
		o.uv = v.texcoord;						// Current position in texture (0 to 1)

		float4 clipPositionToViewSpace = float4(v.texcoord * 2.0 - 1.0, 1.0, 1.0);	// Now: (-1 to 1)

		// Determine which pixel this vertex belongs to
		float4 cameraRay = mul(_InverseProjectionMatrix, clipPositionToViewSpace);

		// The corresponding pixel ray (clipped to -1 to 1)
		o.ray = cameraRay / cameraRay.w;

		return o;
	}

	fixed4 frag(v2f i) : SV_Target	// Fragment Shader - Determines the final color value for each pixel
	{
		// Read depth and reconstruct world position
		float clipSpaceDepthValue = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
		float normalizedWorldSpaceDepthValue = Linear01Depth(clipSpaceDepthValue);

		// Get view and then world positions
		float4 positionInViewSpace = float4(i.ray.xyz * normalizedWorldSpaceDepthValue,1);
		float3 positionInWorldSpace = mul(_InverseViewMatrix, positionInViewSpace).xyz;

		// Ray direction in world space and distance from camera
		float3 rayDirection = normalize(positionInWorldSpace - _WorldSpaceCameraPos.xyz);
		float rayDistance = length(positionInWorldSpace - _WorldSpaceCameraPos.xyz);
		
		// Calculate step size for raymarching
		float stepSize = rayDistance / _RaymarchSteps;
						
		// Camera position
		float3 cameraPositionInWorldSpace = _WorldSpaceCameraPos.xyz;

		// Vertex position
		float3 evaluationPositionInWorldSpace = cameraPositionInWorldSpace + rayDirection.xyz * stepSize;

		// Color of lit fog from directional light
		float3 litFogColor = _DirectionalLightRGBColor * _DirectionalLightIntensity;

#if !defined (INFINITE_FOG)
		// There is a maximum of two intercept points with the fog volume
		float4 firstInterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);
		float4 secondInterceptLocation = float4(0.0f, 0.0f, 0.0f, 0.0f);

		// Determine if the camera is inside or outside of the fog volume
		float cameraInsideFogVolume = NearestEdgeDistancesInFogBox(_WorldSpaceCameraPos.xyz).w;

		if (cameraInsideFogVolume == 1.0f)	// There is only one intercept point
		{
			secondInterceptLocation = DetermineInterceptPoint2(positionInWorldSpace, 5.0f);

			if (secondInterceptLocation.w == 0.0f)
			{
				// First intercept is at evaluation location
				secondInterceptLocation.xyz = positionInWorldSpace;
			}
					   
			evaluationPositionInWorldSpace = _WorldSpaceCameraPos.xyz;
		}
		else
		{
			// Three conditions: no intercept, corner intercept, two intercepts
			// Look for a first intercept point
			firstInterceptLocation = DetermineInterceptPoint1(positionInWorldSpace, 0.05f);
			secondInterceptLocation = DetermineInterceptPoint2(positionInWorldSpace, 0.05f);	
			
			if (firstInterceptLocation.w == 0)
			{
				// No intercept
				return float4(0.0f, 0.0f, 0.0f, 0.0f);
			}

			if (secondInterceptLocation.w == 0.0f)
			{
				// First intercept is at evaluation location
				secondInterceptLocation.xyz = positionInWorldSpace;
			}

			evaluationPositionInWorldSpace = firstInterceptLocation.xyz;
		}

		// Determine if the distance to the scene object is closer than the second box intercept location
		if (length(secondInterceptLocation - evaluationPositionInWorldSpace) <
			length(positionInWorldSpace - evaluationPositionInWorldSpace))
		{
			rayDistance = length(secondInterceptLocation - evaluationPositionInWorldSpace);
		}
		else
		{
			rayDistance = length(positionInWorldSpace - evaluationPositionInWorldSpace);
		}

		// Determine step size
		stepSize = rayDistance / _RaymarchSteps;
#endif

		// Use raymarching to evaluate fog density between camera and farthest opaque object
		float fogDensityPerStep = (stepSize / _DistanceToFogSaturation);
		float finalFogDensity = 0;
		float3 finalFogColor = float3(0.0f, 0.0f, 0.0f);

		// Gather the number of shadow cascades and their weights in the current scene.
		float4 shadowCascadeWeights = GetUnityShadowCascadeWeights(-positionInViewSpace.z);
		
		[loop]	// Start marching across the scene from the camera to the vertex position
		for (int i = 0; i < _RaymarchSteps; i++)
		{
			if (stepSize * i > rayDistance)
			{
				break;
			}
			float evaluationPositionOffset = 0;
#if defined (RANDOMIZED_EVALUATION_POSITION)
			evaluationPositionOffset = (stepSize) * (tex2Dlod(_RandomNoiseTex, float4(i * evaluationPositionInWorldSpace.y * evaluationPositionInWorldSpace.x, evaluationPositionInWorldSpace.z, 0.0f, 0.0f))-0.5f);
#endif

#if defined (INFINITE_FOG)
			float4 distanceFromNearestFogEdges = float4 (-100000, -100000, -100000, 1);
#else
			float4 distanceFromNearestFogEdges = NearestEdgeDistancesInFogBox(evaluationPositionInWorldSpace + evaluationPositionOffset);
#endif
			// Currently not accounting for shadows in fog, so use lit fog color
			float3 stepFogColor = litFogColor;

			{
				// We are inside the predefined fog volume (box shaped)
				float stepFogDensity = fogDensityPerStep;
#if defined (HEIGHT_DENSITY_FALLOFF)
				// Calculate the height density of the fog at the current location
				stepFogDensity *= FogHeightDensity(evaluationPositionInWorldSpace + evaluationPositionOffset);
#endif

#if !defined (INFINITE_FOG) && defined (EDGE_DENSITY_FALLOFF)
				// Calculate the falloff in density at the x and z edges
				stepFogDensity *= FogEdgeDensityXZ(distanceFromNearestFogEdges);

				if (stepFogDensity < 0.00005)
				{
					stepFogDensity = 0;
				}
#endif
				
#if defined(FOG_SHADOWS)
				// Determine whether or not we are sampling in a shadow area in the fog volume
				// REFERENCE: https://aras-p.info/blog/2009/11/04/deferred-cascaded-shadow-maps/ 

				// Step 1: Given the cascade weights used in the shadow maps, determine the 
				// current position in the shadow maps for this pass.
				float4 shadowMapCoordinates = GetUnityShadowMapCoordinates(float4(evaluationPositionInWorldSpace + evaluationPositionOffset, 1), shadowCascadeWeights);

				// Sample the shadow map at the current location to determine if
				// the current location is in a shadow or not. (1 = no shadows, 0 = full shadows)
				float shadowStrength = UNITY_SAMPLE_SHADOW(ShadowMap, shadowMapCoordinates);

				// Use the shadow strength to linearly interpolate between the shadowed and 
				// lighted fog colors. This will add the volumetric shading/light shafts
				// in the fog volumes.
				stepFogColor = lerp(litFogColor * (1 - _ShadowStrength), litFogColor, shadowStrength);
#endif	// FOG_SHADOWS

#if defined(AMBIENT_FOG)
				// Adds the requested percentage of white light to the existing fog color
				stepFogColor = lerp(stepFogColor, _AmbientFogRGBColor, _AmbientLitFog);
#endif	// AMBIENT_FOG

#if defined(NOISY_FOG)
				float3 simplexNoiseEvaluationPosition = float3(	evaluationPositionInWorldSpace.x + evaluationPositionOffset - _NoiseVelocity.x * _Time.x,
																evaluationPositionInWorldSpace.y + evaluationPositionOffset - _NoiseVelocity.y * _Time.x,
																evaluationPositionInWorldSpace.z + evaluationPositionOffset - _NoiseVelocity.z * _Time.x);
				float simplexNoiseValue0to1 = (snoise(simplexNoiseEvaluationPosition / _NoiseSize) / 2.0f) + 0.5f;



#if defined(ADDITIVE_NOISE)
				stepFogDensity *= (1 + _NoiseStrength * simplexNoiseValue0to1);
#else
				stepFogDensity *= (1 - _NoiseStrength * simplexNoiseValue0to1);
#endif // ADDITIVE_NOISE
				
#endif // NOISY_FOG

#if defined(MULTIPLE_LIGHTS)
				// Determine the effect of all other scene lights on this fog step

				// Point light
				float3 pointLightDirection = _PointLightLocation - (evaluationPositionInWorldSpace + evaluationPositionOffset);
				float distanceToLightSource = length(pointLightDirection);
				if (distanceToLightSource < _PointLightRange)
				{
					// Blend the two lights based on their intensities and point light falloff (1/d^2)
					float DivByZero = 0.001f;
					float pointLightIntensityAtCurrentLocation = _PointLightIntensity / (DivByZero + _ConstantAttenuation + 
																						_LinearAttenuation * distanceToLightSource + 
																						_ExponentialAttenuation * pow(distanceToLightSource, 2));
					if (pointLightIntensityAtCurrentLocation < 0)
					{
						pointLightIntensityAtCurrentLocation = 0;
					}

					stepFogColor = lerp(stepFogColor, _PointLightRGBColor, pointLightIntensityAtCurrentLocation);
				}
#endif // MULTIPLE_LIGHTS

				if (finalFogDensity < 1.0f)
				{
					// Accumulate fog
					finalFogDensity += stepFogDensity;
					finalFogColor += stepFogColor * stepFogDensity;
				}
			}

			if (finalFogDensity < 1.0f)
				evaluationPositionInWorldSpace += rayDirection * stepSize;			
		}

		if (finalFogDensity >= 1.0f)
		{
			finalFogColor /= finalFogDensity;
			finalFogDensity = 1.0f;
		}

		return float4(finalFogColor, finalFogDensity);
	}
	ENDCG

	SubShader
	{
		Pass
		{
			ZWrite Off							// Only write to the depth buffer on the first pass

			CGPROGRAM
				#pragma target 3.0							// required for Physics-Based Lighting

				#pragma multi_compile_fwdadd_fullshadows	//	Support for all scene lights and shadows

				#pragma vertex vert
				#pragma fragment frag
			ENDCG
		}
	}

		Fallback off
}