/**********************************************************************************************
* File:         CopyShadows.cs
* Developer:    Joshua Lanman
* Date:         December 1, 2018
* Description:  This script, when attached to a light source, creates a CommandBuffer that will
*               allow the FogShader to use the ShadowMap of the light to create realistic 
*               looking fog/shadow effects.       
**********************************************************************************************/

using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class CopyShadows : MonoBehaviour
{
    /**********************************************************************************************
    *                                  PRIVATE VARIABLES
    **********************************************************************************************/
    // Used to contain the shadow map generated from the initial lighting calculations 
    // for the current frame
    private CommandBuffer MyShadowMap;



   /**********************************************************************************************
   *  Function:        AddShadowMapToCommandBuffer()
   *  Parameters:      None
   *  Return:          None
   *  Description:     Adds a copy of the current shadow map to the command buffer, making it
   *                   available for use in additional rendering steps.    
   **********************************************************************************************/
    void AddShadowMapToCommandBuffer()
    {
        // Create a new CommandBuffer to store the shadow map
        MyShadowMap = new CommandBuffer { name = "Volumetric Fog Shadow Map" };

        // Set a global texture target to gather the shadow map to on each pass
        MyShadowMap.SetGlobalTexture("ShadowMap", new RenderTargetIdentifier(BuiltinRenderTextureType.CurrentActive));

        // Get a handle to this light component
        Light thisLight = transform.GetComponent<Light>();
        if (thisLight)
        {
            // Connect the light source's output to the CommandBuffer
            thisLight.AddCommandBuffer(LightEvent.AfterShadowMap, MyShadowMap);
        }
    }

   /**********************************************************************************************
   *                                   MAIN FUNCTIONS
   **********************************************************************************************/
    /**********************************************************************************************
    *  Function:        Start()
    *  Parameters:      None
    *  Return:          None
    *  Description:     Use this function for initialization/setup.
    **********************************************************************************************/
    void Start()
    {
        // Create the shadow map and add it to the command buffer
        AddShadowMapToCommandBuffer();
    }

    /**********************************************************************************************
    *  Function:        ShadowMap()
    *  Parameters:      None
    *  Return:          None
    *  Description:     Use this function to get a copy of the command buffer containing the
    *                   shadow map data.
    **********************************************************************************************/
    CommandBuffer ShadowMap()
    {
        return MyShadowMap;
    }
}