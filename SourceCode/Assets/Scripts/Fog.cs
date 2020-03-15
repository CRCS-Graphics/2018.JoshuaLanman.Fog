/**********************************************************************************************
* File:         Fog.cs
* Developer:    Joshua Lanman
* Date:         December 1, 2018
* Description:  This script, when attached to a camera, generates fog in the designated 
*               fogVolume created by the user.This script uses the deferred rendering path to
*               create the requested fog effects in the scene.
**********************************************************************************************/

using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Rendering;

[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]

public class Fog : MonoBehaviour
{
    /**********************************************************************************************
    *                             PUBLIC VARIABLES (VISIBLE IN EDITOR)
    **********************************************************************************************/
    // public Vector3 playerPosition;

    [Header("Required Shaders")]
    public Shader calculateFogDensity;
    public Shader blendFogWithScene;

    [Header("Required Assets")]
    public Transform directionalLight = null;
    public bool scenewideFog = false;
    public GameObject fogVolume = null;
    public bool useGlobalXYZ = true;
    public Texture2D randomNoiseTexture;

    [Header("Additional Lights")]
    public bool allowExtraLights = false;
    public Transform pointLight = null;
    [Range(0, 1.0f)] public float constantAttenuation = 0.1f;
    [Range(0, 0.1f)] public float linearAttenuation = 0.00005f;
    [Range(0, 0.01f)] public float exponentialAttenuation = 0.0005f;

    [Header("Fog Density")]
    [Tooltip("Higher values have better quality, while lower values have better performance (higher FPS).")]
    [Range(2, 256)] public int maxNumberOfSteps = 128;
    [Tooltip("Viewing distance through fog where (if no other options are turned on) fog will completely saturate the pixel. This is an approximation of the Beer-Lambert Law.")]
    public float distanceToFogSaturation = 100.0f;
    [Tooltip("Randomized evaluation points are used to soften visible artifacts.")]
    public bool randomizeEvaluationPoints = false;

    [Space(20)]
    [Tooltip("Density varies from thick at bottom to thin (or none) at top of fog volume.")]
    public bool useHeightDensityFalloff = false;
    [Tooltip("Default: Linear fog distribution.")]
    public bool exponentialFalloffInY = false;
    [Tooltip("Bottom height to begin fog density falloff.")]
    public float heightToStartFalloffAt = 0.0f;
    [Tooltip("For Sceenwide fog: Distance to perform falloff over.")]
    public float YFalloffDistance = 100.0f;

    [Space(20)]
    [Tooltip("Density varies from thick at middle to thin (or none) at sides of fog volume.")]
    public bool useEdgeDensityFalloff = false;
    [Tooltip("Default: Linear fog distribution.")]
    public bool exponentialFalloffInXZ = false;
    [Tooltip("Start density variation at 0 to 100% distance from edge to middle of fog volume.")]
    [Range(0, 100)] public float fogFalloffInX = 0.00f;
    [Tooltip("Start density variation at 0 to 100% distance from edge to middle of fog volume.")]
    [Range(0, 100)] public float fogFalloffInZ = 0.00f;

    [Space(10)]
    [Header("Shadows")]
    [Tooltip("Enable shadowed fog.")]
    public bool useShadowsInFog = false;
    [Tooltip("Increases shadow strength (percentage) by decreasing the strength of the directed light source in the shadow area.")]
    [Range(0, 100)] public float shadowStrength = 80.0f;

    [Space(10)]
    [Header("Fog Noise")]
    [Tooltip("Enable noisy fog.")]
    public bool useNoiseInFog = false;
    [Tooltip("Enable additive noise (Increases fog density in noisy areas). Default is subtractive fog.")]
    public bool useAdditiveNoise = false;
    [Range(0, 1)] public float noiseStrength = 0.0f;
    [Tooltip("Increases the size of the noise artifacts.")]
    [Range(1, 500)] public float noiseSize = 1.0f;
    [Tooltip("Velocity is used to give the fog movement within the volume (simulates wind).")]
    public Vector3 noiseVelocity;

    [Space(10)]
    [Header("Atmospheric Lighting")]
    [Tooltip("Enable ambient fog (Adds lighting to all fog, including shadows).")]
    public bool useAmbientLitFog = false;
    [Range(0, 1)] public float ambientLitFog = 0.00f;
    [Tooltip("xyz are the RGB color of the ambient fog (values from 0.0 to 1.0) .")]
    public Vector3 ambientFogColor;

    /**********************************************************************************************
    *                             PRIVATE VARIABLES (NOT VISIBLE IN EDITOR)
    **********************************************************************************************/
   // Box CGs
    private Vector3 boxCG;
    private Vector3 boxLeft;
    private Vector3 boxRight;
    private Vector3 boxFront;
    private Vector3 boxBack;
    private Vector3 boxTop;
    private Vector3 boxBottom;

    //"Box Normals"
    private Vector3 leftNormal;
    private Vector3 rightNormal;
    private Vector3 frontNormal;
    private Vector3 backNormal;
    private Vector3 topNormal;
    private Vector3 bottomNormal;



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

        CalculateFogDensityAndColor.SetFloat("_FarClipPlane", CurrentCamera.farClipPlane);

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

        // Orientation of fog volume
        if (useGlobalXYZ)
        {
            calculateFogDensityAndColor.EnableKeyword("USE_GLOBAL_XYZ");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("USE_GLOBAL_XYZ");
        }
        CalculateFogDensityAndColor.SetVector("_FogUp", fogVolume.transform.up);
        CalculateFogDensityAndColor.SetVector("_FogForward", fogVolume.transform.forward);
        CalculateFogDensityAndColor.SetVector("_FogRight", fogVolume.transform.right);
        CalculateFogDensityAndColor.SetTexture("_RandomNoiseTex", randomNoiseTexture);


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
        CalculateFogDensityAndColor.SetFloat("_ConstantAttenuation", constantAttenuation);
        CalculateFogDensityAndColor.SetFloat("_LinearAttenuation", linearAttenuation);
        CalculateFogDensityAndColor.SetFloat("_ExponentialAttenuation", exponentialAttenuation);

        // *** Fog Density ***

        // Number of steps/samples to take for each frame
        CalculateFogDensityAndColor.SetInt("_RaymarchSteps", maxNumberOfSteps);

        // Distance at which fog fully saturates the current pixel
        CalculateFogDensityAndColor.SetFloat("_DistanceToFogSaturation", distanceToFogSaturation);

        // Use randomized evaluation points?
        if (randomizeEvaluationPoints)
        {
            calculateFogDensityAndColor.EnableKeyword("RANDOMIZED_EVALUATION_POSITION");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("RANDOMIZED_EVALUATION_POSITION");
        }

        // Use height density falloff?
        if (useHeightDensityFalloff)
        {
            calculateFogDensityAndColor.EnableKeyword("HEIGHT_DENSITY_FALLOFF");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("HEIGHT_DENSITY_FALLOFF");
        }

        // Use linear or exponential height falloff?
        if (exponentialFalloffInY)
        {
            calculateFogDensityAndColor.EnableKeyword("EXPONENTIAL_HEIGHT_DENSITY_FALLOFF");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("EXPONENTIAL_HEIGHT_DENSITY_FALLOFF");
        }

        // Where does falloff begin? This is either relative to bottom of box or to global cg,
        // depending on if the fog is scenewide or not
        CalculateFogDensityAndColor.SetFloat("_HeightToStartFalloffAt", heightToStartFalloffAt);
        CalculateFogDensityAndColor.SetFloat("_YFalloffDistance", Mathf.Abs(YFalloffDistance));

        // Fog volume falloff in x/z directions
        if (useEdgeDensityFalloff)
        {
            calculateFogDensityAndColor.EnableKeyword("EDGE_DENSITY_FALLOFF");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("EDGE_DENSITY_FALLOFF");
        }
        // Use linear or exponential height falloff?
        if (exponentialFalloffInXZ)
        {
            calculateFogDensityAndColor.EnableKeyword("EXPONENTIAL_EDGE_DENSITY_FALLOFF");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("EXPONENTIAL_EDGE_DENSITY_FALLOFF");
        }
        CalculateFogDensityAndColor.SetFloat("_FogEdgeFalloffInX", fogFalloffInX / 100.0f);
        CalculateFogDensityAndColor.SetFloat("_FogEdgeFalloffInZ", fogFalloffInZ / 100.0f);

        // Knockdown on light strength in shadows
        if (useShadowsInFog)
        {
            calculateFogDensityAndColor.EnableKeyword("FOG_SHADOWS");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("FOG_SHADOWS");
        }
        CalculateFogDensityAndColor.SetFloat("_ShadowStrength", shadowStrength / 100.0f);

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
        if (useAdditiveNoise)
        {
            calculateFogDensityAndColor.EnableKeyword("ADDITIVE_NOISE");
        }
        else
        {
            calculateFogDensityAndColor.DisableKeyword("ADDITIVE_NOISE");
        }
        CalculateFogDensityAndColor.SetFloat("_NoiseStrength", noiseStrength);
        CalculateFogDensityAndColor.SetFloat("_NoiseSize", noiseSize);
        CalculateFogDensityAndColor.SetVector("_NoiseVelocity", noiseVelocity);

        // *** Atmospheric Lighting ***

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
        CalculateFogDensityAndColor.SetVector("_AmbientFogRGBColor", ambientFogColor);

        BlendFogWithScene(source, destination, CalculateFogDensityAndColor);

        // *** Fog Box CGs and Normals ***
        // CGs
        boxCG.x = fogVolume.GetComponent<BoxGeometry>().BoxCG.x;
        boxCG.y = fogVolume.GetComponent<BoxGeometry>().BoxCG.y;
        boxCG.z = fogVolume.GetComponent<BoxGeometry>().BoxCG.z;
        boxLeft.x = fogVolume.GetComponent<BoxGeometry>().Left.x;
        boxLeft.y = fogVolume.GetComponent<BoxGeometry>().Left.y;
        boxLeft.z = fogVolume.GetComponent<BoxGeometry>().Left.z;
        boxRight.x = fogVolume.GetComponent<BoxGeometry>().Right.x;
        boxRight.y = fogVolume.GetComponent<BoxGeometry>().Right.y;
        boxRight.z = fogVolume.GetComponent<BoxGeometry>().Right.z;
        boxFront.x = fogVolume.GetComponent<BoxGeometry>().Front.x;
        boxFront.y = fogVolume.GetComponent<BoxGeometry>().Front.y;
        boxFront.z = fogVolume.GetComponent<BoxGeometry>().Front.z;
        boxBack.x = fogVolume.GetComponent<BoxGeometry>().Back.x;
        boxBack.y = fogVolume.GetComponent<BoxGeometry>().Back.y;
        boxBack.z = fogVolume.GetComponent<BoxGeometry>().Back.z;
        boxTop.x = fogVolume.GetComponent<BoxGeometry>().Top.x;
        boxTop.y = fogVolume.GetComponent<BoxGeometry>().Top.y;
        boxTop.z = fogVolume.GetComponent<BoxGeometry>().Top.z;
        boxBottom.x = fogVolume.GetComponent<BoxGeometry>().Bottom.x;
        boxBottom.y = fogVolume.GetComponent<BoxGeometry>().Bottom.y;
        boxBottom.z = fogVolume.GetComponent<BoxGeometry>().Bottom.z;
        // Normals
        leftNormal.x = fogVolume.GetComponent<BoxGeometry>().LeftFace.x;
        leftNormal.y = fogVolume.GetComponent<BoxGeometry>().LeftFace.y;
        leftNormal.z = fogVolume.GetComponent<BoxGeometry>().LeftFace.z;
        rightNormal.x = fogVolume.GetComponent<BoxGeometry>().RightFace.x;
        rightNormal.y = fogVolume.GetComponent<BoxGeometry>().RightFace.y;
        rightNormal.z = fogVolume.GetComponent<BoxGeometry>().RightFace.z;
        frontNormal.x = fogVolume.GetComponent<BoxGeometry>().FrontFace.x;
        frontNormal.y = fogVolume.GetComponent<BoxGeometry>().FrontFace.y;
        frontNormal.z = fogVolume.GetComponent<BoxGeometry>().FrontFace.z;
        backNormal.x = fogVolume.GetComponent<BoxGeometry>().BackFace.x;
        backNormal.y = fogVolume.GetComponent<BoxGeometry>().BackFace.y;
        backNormal.z = fogVolume.GetComponent<BoxGeometry>().BackFace.z;
        topNormal.x = fogVolume.GetComponent<BoxGeometry>().TopFace.x;
        topNormal.y = fogVolume.GetComponent<BoxGeometry>().TopFace.y;
        topNormal.z = fogVolume.GetComponent<BoxGeometry>().TopFace.z;
        bottomNormal.x = fogVolume.GetComponent<BoxGeometry>().BottomFace.x;
        bottomNormal.y = fogVolume.GetComponent<BoxGeometry>().BottomFace.y;
        bottomNormal.z = fogVolume.GetComponent<BoxGeometry>().BottomFace.z;

        // Send to shader: Fog Box CGs and Normals
        CalculateFogDensityAndColor.SetVector("_LeftCG", boxLeft);
        CalculateFogDensityAndColor.SetVector("_LeftNormal", leftNormal);
        CalculateFogDensityAndColor.SetVector("_RightCG", boxRight);
        CalculateFogDensityAndColor.SetVector("_RightNormal", rightNormal);
        CalculateFogDensityAndColor.SetVector("_FrontCG", boxFront);
        CalculateFogDensityAndColor.SetVector("_FrontNormal", frontNormal);
        CalculateFogDensityAndColor.SetVector("_BackCG", boxBack);
        CalculateFogDensityAndColor.SetVector("_BackNormal", backNormal);
        CalculateFogDensityAndColor.SetVector("_TopCG", boxTop);
        CalculateFogDensityAndColor.SetVector("_TopNormal", topNormal);
        CalculateFogDensityAndColor.SetVector("_BottomCG", boxBottom);
        CalculateFogDensityAndColor.SetVector("_BottomNormal", bottomNormal);
    }
}