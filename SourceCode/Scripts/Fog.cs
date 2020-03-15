/**********************************************************************************************
* File:         Fog.cs
* Developer:    Joshua Lanman
* Date:         September 1, 2018
* Description:  This script, when attached to a camera, generates fog in the designated 
*               fogVolume created by the user.This script uses the deferred rendering path to
*               create the requested fog effects in the scene.
**********************************************************************************************/

using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]

public class Fog : MonoBehaviour
{
    /**********************************************************************************************
    *                             PUBLIC VARIABLES (VISIBLE IN EDITOR)
    **********************************************************************************************/
    [Header("Required Shaders")]
    public Shader calculateFogDensity;
    public Shader blendFogWithScene;

    [Header("Required Assets")]
    public Transform directionalLight = null;
    public bool scenewideFog = false;
    public GameObject fogVolume = null;    

    [Header("Additional Lights")]
    public bool allowExtraLights = false;
    public Transform pointLight = null;
    
    [Header("Fog Density")]
    [Range(8, 256)] public int maxNumberOfSteps = 128;
    public float distanceToFogSaturation = 100.0f;
    public bool useHeightDensityFalloff = false;
    public float heightToStartFalloffAt = 0.0f;
    [Range(0, 1.0f)] public float exponentialHeightDensity = 1.0f;
    public bool useEdgeDensityFalloff = false;
    [Range(0, 1)] public float fogFalloffInX = 0.00f;
    // [Range(0, 1)] public float fogFalloffInY = 0.00f;
    [Range(0, 1)] public float fogFalloffInZ = 0.00f;
    public bool useShadowsInFog = false;
    [Range(0, 1)] public float shadowStrength = 0.80f;
    public bool useAmbientLitFog = false;
    [Range(0, 1)] public float ambientLitFog = 0.10f;
    

    [Header("Fog Noise")]
    public bool useNoiseInFog = false;
    [Range(0, 5)] public float noiseStrength = 0.0f;
    public Vector3 noiseVelocity;

    [Header("############# Testing and Debug #############")]
    public bool fogColorByCascade = false;

    /*
       [Header("Physical coefficients")] 

      
       // Beer-Lambert Law

       // Used to adjust light transmittance through a volume (Beer-Lambert Law) with outscattering
       [Range(0, 0.1f)] public float _ExtinctionCoefficient = 0.02f;
   */



    /**********************************************************************************************
    *                                  PRIVATE VARIABLES
    **********************************************************************************************/



    /**********************************************************************************************
    *                                    CLASS FUNCTIONS
    **********************************************************************************************/

    bool RequiredResourcesAreMissing()
    {
        // References: https://interplayoflight.wordpress.com/2015/07/03/adventures-in-postprocessing-with-unity/

        return !(calculateFogDensity && blendFogWithScene && fogVolume && directionalLight);
    }

    private Material calculateFogDensityAndColor;
    public Material CalculateFogDensityAndColor
    {
        get
        {
            if (!calculateFogDensityAndColor && calculateFogDensity)
            {
                calculateFogDensityAndColor = new Material(calculateFogDensity);
                calculateFogDensityAndColor.hideFlags = HideFlags.HideAndDontSave;
            }

            return calculateFogDensityAndColor;
        }
    }

    private Material finalBlendedSceneWithFog;
    public Material FinalBlendedSceneWithFog
    {
        get
        {
            if (!finalBlendedSceneWithFog && blendFogWithScene)
            {
                finalBlendedSceneWithFog = new Material(blendFogWithScene);
                finalBlendedSceneWithFog.hideFlags = HideFlags.HideAndDontSave;
            }

            return finalBlendedSceneWithFog;
        }
    }

    private Camera currentCamera;
    public Camera CurrentCamera
    {
        get
        {
            if (!currentCamera)
                currentCamera = GetComponent<Camera>();
            return currentCamera;
        }
    }

    private void BlendFogWithScene(RenderTexture source, RenderTexture destination, Material fogToBlendWithScene)
    {
        // References: Siim Raudsepp Unity Project: Volumetric Shader

        RenderTextureFormat HDRRenderTextureFormat = RenderTextureFormat.ARGBHalf; 
        RenderTexture fogRenderTexture = RenderTexture.GetTemporary(source.width, source.height, 0, HDRRenderTextureFormat);
        Graphics.Blit(source, fogRenderTexture, fogToBlendWithScene);

        FinalBlendedSceneWithFog.SetTexture("FogRenderTexture", fogRenderTexture);
        Graphics.Blit(source, destination, FinalBlendedSceneWithFog);

        RenderTexture.ReleaseTemporary(fogRenderTexture);
    }

	public static float Perlin3D(float x, float y, float z)
	{
		// References: https://www.youtube.com/watch?v=Aga0TBJkchM

		float AB = Mathf.PerlinNoise(x, y);
		float BC = Mathf.PerlinNoise(y, z);
		float AC = Mathf.PerlinNoise(x, z);

		float BA = Mathf.PerlinNoise(y, x);
		float CB = Mathf.PerlinNoise(z, y);
		float CA = Mathf.PerlinNoise(z, x);

		return Mathf.Clamp01((AB + BC + AC + BA + CB + CA) / 6.0f);
	}



    /**********************************************************************************************
    *                                   MAIN FUNCTIONS
    **********************************************************************************************/

    // Render these effects after opaque objects are rendered and before the transparent objects
    [ImageEffectOpaque]

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (RequiredResourcesAreMissing())
        {
            Graphics.Blit(source, destination);
            return;
        }

        // Pass the requisite camera matrices needed by all of the shaders
        Shader.SetGlobalMatrix("_InverseViewMatrix", CurrentCamera.cameraToWorldMatrix);
        Shader.SetGlobalMatrix("_InverseProjectionMatrix", CurrentCamera.projectionMatrix.inverse);

        // *** START OF Pass the additional requested settings/values to the fog density shader *** //

        // *** Required Assets ***

        // Directed light values
        CalculateFogDensityAndColor.SetFloat("_DirectionalLightIntensity", directionalLight.GetComponent<Light>().intensity);
        CalculateFogDensityAndColor.SetVector("_DirectionalLightDirection", directionalLight.GetComponent<Light>().transform.forward);
        CalculateFogDensityAndColor.SetColor("_DirectionalLightRGBColor", directionalLight.GetComponent<Light>().color);

        // Stretch fog to cover entire scene?
        if (scenewideFog)
        {
            calculateFogDensityAndColor.EnableKeyword("INFINITE_FOG");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("INFINITE_FOG");
        }

        // CG of fog in the scene coordinate system
        CalculateFogDensityAndColor.SetVector("_FogWorldPosition", fogVolume.transform.localPosition);

        // width/height/length of fog volume
        CalculateFogDensityAndColor.SetVector("_FogDimensions", fogVolume.transform.localScale);


        // *** Additional Lights ***
        // Allow extra lights to interact with this fog volume?
        if (allowExtraLights)
        {
            calculateFogDensityAndColor.EnableKeyword("MULTIPLE_LIGHTS");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("MULTIPLE_LIGHTS");
        }

        // Point light values
        CalculateFogDensityAndColor.SetFloat("_PointLightIntensity", pointLight.GetComponent<Light>().intensity);
        CalculateFogDensityAndColor.SetColor("_PointLightRGBColor", pointLight.GetComponent<Light>().color);
        CalculateFogDensityAndColor.SetVector("_PointLightLocation", pointLight.position);
        CalculateFogDensityAndColor.SetFloat("_PointLightRange", pointLight.GetComponent<Light>().range);

        // *** Fog Density ***

        // Number of steps/samples to take for each frame
        CalculateFogDensityAndColor.SetInt("_RaymarchSteps", maxNumberOfSteps);

        // Distance at which fog fully saturates the current pixel
        CalculateFogDensityAndColor.SetFloat("_DistanceToFogSaturation", distanceToFogSaturation);

        // Use height density falloff?
        if (useHeightDensityFalloff)
        {
            calculateFogDensityAndColor.EnableKeyword("HEIGHT_DENSITY_FALLOFF");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("HEIGHT_DENSITY_FALLOFF");
        }

        // Where does falloff begin? This is either relative to bottom of box or to global cg,
        // depending on if the fog is scenewide or not
        CalculateFogDensityAndColor.SetFloat("_HeightToStartFalloffAt", heightToStartFalloffAt);

        // How much the density of the fog falls off in vertical direction (if using height fog)
        CalculateFogDensityAndColor.SetFloat("_ExponentialHeightDensity", exponentialHeightDensity);

        // Fog volume falloff in x/z directions
        if (useEdgeDensityFalloff)
        {
            calculateFogDensityAndColor.EnableKeyword("EDGE_DENSITY_FALLOFF");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("EDGE_DENSITY_FALLOFF");
        }
        CalculateFogDensityAndColor.SetFloat("_FogEdgeFalloffInX", fogFalloffInX);
        CalculateFogDensityAndColor.SetFloat("_FogEdgeFalloffInZ", fogFalloffInZ);

        // Knockdown on light strength in shadows
        if (useShadowsInFog)
        {
            calculateFogDensityAndColor.EnableKeyword("FOG_SHADOWS");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("FOG_SHADOWS");
        }
        CalculateFogDensityAndColor.SetFloat("_ShadowStrength", shadowStrength);

        //  Ambient Fog: Used to bleed some of the lit fog into shadowed areas
        if (useAmbientLitFog)
        {
            calculateFogDensityAndColor.EnableKeyword("AMBIENT_FOG");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("AMBIENT_FOG");
        }
        CalculateFogDensityAndColor.SetFloat("_AmbientLitFog", ambientLitFog);



        // *** Fog Noise ***

        //  Noise Strength: Used to adjust the influence of simplex noise on the fog volume
        if (useNoiseInFog)
        {
            calculateFogDensityAndColor.EnableKeyword("NOISY_FOG");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("NOISY_FOG");
        }
        CalculateFogDensityAndColor.SetFloat("_NoiseStrength", noiseStrength);
        CalculateFogDensityAndColor.SetVector("_NoiseVelocity", noiseVelocity);

        // *** Testing and Debug ***

        // ********** START DEBUG ********** //
        if (fogColorByCascade)
        {
            calculateFogDensityAndColor.EnableKeyword("COLOR_FOG_BY_CASCADES");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("COLOR_FOG_BY_CASCADES");
        }
        // ********** END DEBUG ********** //



        // *** MISC (NOT CURRENTLY IN USE) ***

        // Extinction Coefficient (Beer-Lambert Law) for atmospheric scattering
        //      CalculateFogDensityAndColor.SetFloat("_ExtinctionCoef", _ExtinctionCoefficient);


        // *** END OF Pass the additional requested settings/values to the fog density shader *** //

        
        BlendFogWithScene(source, destination, CalculateFogDensityAndColor);
    }
}